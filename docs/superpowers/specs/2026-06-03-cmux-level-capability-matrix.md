# cmux-Level Capability Matrix

- **Date:** 2026-06-03
- **Purpose:** Turn the cmux-level ambition into a concrete implementation and verification ledger.
- **Companion plan:** `docs/superpowers/plans/2026-06-03-cmux-level-workbench.md`
- **Companion design:** `docs/superpowers/specs/2026-06-03-cmux-level-workbench-design.md`
- **Delivery contract:** `docs/superpowers/specs/2026-06-03-cmux-level-delivery-contract.md`

This document is the "no hand-waving" layer. The plan says what tracks exist. The design says what experience we want. This matrix says exactly what must be true before we can claim parity-level usefulness.

## Reference Observations

Public reference docs checked on 2026-06-03:

- `https://cmux.com/` describes the core product surface as a native macOS terminal with vertical tabs, split panes, embedded browser, notification rings, a CLI/socket API, libghostty rendering, and customizable shortcuts.
- `https://cmux.com/docs/getting-started` positions install, CLI setup, auto-updates, and session restore as first-run concepts rather than hidden developer features.
- `https://cmux.com/docs/session-restore` frames restore around app-owned layout, working directories, best-effort terminal scrollback, browser URL/history, and supported agent resume hooks.
- `https://cmux.com/docs/browser-automation` treats browser surfaces as scriptable targets: navigation, wait, DOM interaction, inspection, screenshot, JavaScript, storage, tabs, console/errors, frames, dialogs, and downloads.
- `https://cmux.com/docs/notifications` defines notifications as a lifecycle: received, unread, read, cleared, with workspace badges and jump behavior.

Conductor does not need to copy naming or visuals. It does need to reach the same human outcome: a user can run multiple agent-heavy tasks, leave, return, inspect, automate, and recover without guessing.

## Capability Levels

Use these levels for every row below.

| Level | Meaning | Allowed claim |
| --- | --- | --- |
| L0 | Not started or only a visual placeholder exists. | Do not mention as shipped. |
| L1 | Basic code path exists, but no full user loop or diagnostics. | Internal preview only. |
| L2 | User-visible feature works and has protocol or test coverage. | Shipped with known limitations. |
| L3 | Feature survives failure cases, has diagnostics, docs, and release coverage. | Parity-level useful. |

## Current Capability Snapshot

This snapshot separates primary workbench capability from secondary AI-channel
ledger items. AI-channel rows are kept for traceability only and are not allowed
to drive the next implementation slice while the primary workbench rows still
have open L2/L3 gaps.

| Area | Current level | Evidence in repo | Main gap |
| --- | --- | --- | --- |
| Local control protocol | L2 | `ConductorControlServer`, `ConductorControlRouter`, `ConductorCLI`, `control-smoke.sh`, `CONDUCTOR_CONTROL_SOCKET_PATH` isolated smoke path, terminal resume-agent dry-run/send command, browser select/snapshot/screenshot/click/fill/press/wait/find/evaluate commands, file open/reveal/save/snapshot commands with typed negative fixture coverage, update status/check/download/cancel/rehearse-install/install commands, local browser and file fixture smoke, update fixture smoke, diagnostics export, recent control error history, isolated dogfood script. | Editor-local file text is still saved through a UI save request unless CLI supplies `--text`; broader typed state errors remain. |
| Workspace create/select/split/send | L2 | CLI and socket smoke can create workspace, split, send text, open browser; `dogfood-workbench.sh` creates three workspaces with split terminals, browser tabs, notifications, screenshots, and diagnostics in an isolated state path. | Needs dogfood script with real supported agent tasks and resume/completion assertions. |
| Session journal and restore | L2 normal + fallback path | `ConductorSessionJournal`, semantic workspace/terminal/web/file events, journal replay engine, previous valid compact snapshot, `session.restorePrevious`/CLI/command-palette recovery action, restore-health diagnostics with missing file paths, startup recovery toast, in-app `sessionRecovery` event, Settings > Overview recovery check with severity rows, jump targets, user-impact copy, and primary actions, `session inspect` structured `surfaceIssues` with `impact` and `primaryAction`, normal relaunch verification for selected workspace/web tabs/exact browser URL/restored browser page text after `browser.select`/restored browser scroll/back/forward fallback/file tabs/unread attention/restored terminal title/cwd/readable output, supported-agent resume metadata plus explicit `terminal.resumeAgent` and `terminal.resumeAgents` dry-run verification, non-dry-run current-workspace batch resume verified through a local fake supported-agent binary, restored-terminal `fresh-after-restore` process explanation, file-open persistence fix, real terminal command submission in dogfood, `dogfood-workbench.sh` active restore-previous verification, corrupt-current-state fallback verification, and isolated `restoredFromJournal` launch smoke. | Actual process reattach implementation, no-reload browser session restore, broader restore-inspector real-world failure coverage, and real external-agent continuation dogfood missing. |
| Terminal restore | L2 useful context restore | `terminal.rename`, `terminal.title`, `terminal.cwd`, `terminal.resumeAgent`, `terminal.resumeAgents`, bounded VT/plain scrollback snapshots, delayed snapshot replay after fresh Ghostty surface attachment, graceful protocol `quit`, terminal-tab persisted agent snapshots, last command snapshots, active search snapshots, workspace metadata/control-protocol exposure, context-menu resume/copy actions, command-palette workspace resume action, `session inspect` process status, and dogfood verification for restored terminal user title, cwd, readable visible output, canonical single-terminal resume command, current-workspace batch resume target, non-dry-run batch command delivery via a fake supported-agent binary, and `terminal_process_restarted` explanation after ordinary relaunch. | Actual process reattach implementation, real external-agent dogfood, and broader non-fixture terminal history coverage missing. |
| AI channel management | Deferred L1/L2 ledger, not primary progress | `AIChannelDefinition`, `AIChannelCatalog`, `AIChannelState`, `TerminalAIChannelBinding`, global default channel persistence, enable/disable, priority ordering, custom OpenAI-compatible endpoint configuration, lightweight health assessment, terminal-tab override persistence, default inheritance, duplicate/workspace-copy preservation, per-surface effective environment injection, `aiChannel.list`, `aiChannel.configure`, `aiChannel.setDefault`, `terminal.aiChannel`, `terminal.setAIChannel`, CLI `ai-channel list|configure|set-default|enable|disable|set-priority` and `terminal channel get|set|clear`, redacted diagnostics/surface summaries, and `requiresNewSurface` reporting for already-running terminals. | Frozen except regression fixes until session life, browser surfaces, attention, command/action consistency, native UX, updates, diagnostics, and real dogfood gates meet the primary bar. |
| Browser restore | L2 explicit restore | Web tab metadata, explicit navigation entries/current index/scroll position, interaction state field, archived WebKit state blobs when available, `browser.select`, restore inspector surfacing blank/error/history/scroll issues, and dogfood verification for restored browser URL/page text, restored scroll position, restored `browser back` to `release-1`, and restored `browser forward` to `release-2`. | True no-reload WebKit restoration and broader non-fixture site coverage missing. |
| Notification reliability | L2 foundation | `ConductorAttentionEvent`, `ConductorAttentionStore`, agent/control event persistence, targetable CLI notifications, protocol create/list/focus/focusLatest/markRead/clear/test, command-palette jump-latest and mark-workspace-read actions, diagnostics unread count, toolbar notification panel, workspace/sidebar/tab unread indicators, banner failure toast, settings permission-state row plus test delivery action, per-terminal/source duplicate coalescing with merged-count UI, terminal desktop-notification escape ingestion, background command-finished events for failed or long-running unattended commands, terminal-attention system-banner attempts, agent/terminal banner click-through to stored attention events with read-state clearing, pure delivery-policy tests for allowed/denied/not-requested/unavailable/unknown/success/failure outcomes, and notification-panel/control-smoke coverage for store/show/jump/read/focus plus selected-workspace-first and global-fallback latest-unread behavior. | Full end-to-end `.app` permission-state automation missing. |
| Browser automation | L2 positive and negative fixture coverage | Open/select/navigate/reload/back/forward, bounded `browser.snapshot`, visible-viewport PNG `browser.screenshot`, basic `browser.click/fill/press/wait/find/evaluate` through protocol/CLI on the visible WebKit tab, local fixture smoke for the positive path, restored-tab selection/history/scroll in dogfood, typed negative fixture coverage for common selector/text/script/timeout failures, `browser.wait` support for load/ready, selector/visible, text, URL, title, idle/network-idle, hidden, and gone/detached states, safe frame summaries in `browser.snapshot` with same-origin text/counts and explicit inaccessible-frame reasons, same-origin frame target routing via `frame-N >> selector` for click/fill/press/wait, frame-aware `browser.find`, and `browser.evaluate --frame frame-N`, native JS alert/confirm/prompt sheets, persisted download state, toolbar download status, Finder reveal, `surface.list` download diagnostics, recent browser runtime events for console/error/unhandled rejection persisted on the tab, cleared on navigation/reload/history movement, and exposed through `browser.snapshot`, `surface.list`, diagnostics, restore-health warning issues, and a compact toolbar error menu, plus local binary download, runtime-error fixture coverage, smoke coverage that clean navigation resets stale runtime events, and protocol stress coverage that opens 10 tabs and runs frame fill/click/wait/find/evaluate on each. | Cross-origin action routing, long-running/browser-scale stress, safe-bridge hardening, richer per-event source mapping, and broader history/scroll restore coverage missing. |
| Workspace intelligence | L2 foundation | `WorkspaceMetadataSnapshot`, `WorkspaceMetadataService`, `workspace.metadata`, `ConductorCLI workspace metadata`, and `control-smoke.sh` selected-workspace plus non-selected workspace metadata coverage expose root/project, counts, terminal/file/web arrays, ports, local dev-server summaries, active agents, unread work, health, and refresh time. Sidebar rows consume cached metadata for root subtitle, port/health signals, and native hover details. File tabs now keep model-backed synchronized editor buffers so `file.save` can write current open-editor text without `--text`. The workspace panel includes a list-plus-inspector view with root, health, terminal summaries, workspace-owned file/web tab lists, local service quick-open rows, unread/running state, switch, cross-workspace tab jump, first-service open, and Finder actions. Top workspace tabs consume the same snapshot for compact port/health indicators, hover detail, and root/port context actions. | Richer per-tab actions, real-agent context, and explicit scoped-refresh performance proof remain. |
| Command layer | L2 foundation | `ConductorShellCommand` canonical metadata registry, command palette rows generated from the registry, visible outcome descriptions, attention jump/read commands, browser back/forward commands, file external-open/reveal commands, workspace rename/duplicate/close-other/close-right/close-current/open-root/open-service commands, recent-command memory, current-surface/context weighted ranking, small ranking badges/tooltips, `command.list` metadata/disabled reasons/ranking model, `command.run` disabled-reason errors, shortcut preferences, shortcut profile import/export UI, smoke coverage for command metadata/ranking/attention/web/file/workspace-command behavior including `rename-workspace`, shortcut-profile autorun coverage, high-frequency toolbar/sidebar/web/file/workspace/search actions routed through `performCommand`, top file/web/workspace context actions selecting their target before command execution, workspace overview/inspector root and first-service actions routed through commands, macOS menu entries for web back/forward, current-file open/reveal, workspace rename/close/root/service actions verified by eleven-item menu autorun, and direct shell-panel shortcut containment coverage for settings, command palette, workspace overview, notifications, and terminal search. | Remaining row-specific toolbar/sidebar/context action audit and broader native menu coverage remain. |
| Native UX polish | L1 | Multiple theme/UI passes exist. | Token audit, hover help audit, panel consistency, scroll/drag thresholds. |
| Updates | L2 safety fixture | GitHub updater work, release packaging scripts, hourly automatic check loop with repeated-failure backoff diagnostics, update control methods, transient manifest override, isolated update download directory, and `Scripts/update-fixture.sh` covering available update, slow local-copy progress samples, in-flight cancel with retryable state, verified signed `.app` download, dry-run installer staging/codesign rehearsal, and checksum mismatch. | Top chrome progress polish, speed/retry UX, release notes UI, and destructive replacement/relaunch rehearsal. |
| Observability | L1/L2 | Signposts, model checks, smoke scripts, isolated `check-conductor.sh` gate entry, `dogfood-workbench.sh`, expanded `stress-conductor.sh`, `update-fixture.sh`, redacted diagnostics bundle export, recent control error history, recent main-thread stalls, performance budget targets, control-driven budget samples, UI panel open samples, throttled terminal scroll-frame samples, precise-scroll coalescing diagnostics, performance coverage/over-budget report, dogfood and update-check performance threshold gates, release-gate screenshot capture, and fake-agent resume execution coverage. | Full test/bundle gate run, broader manual scroll-feel validation, and real external-agent dogfood missing. |
| Public docs | L1/L2 | README, getting started, API, notifications, session restore, updating, security, troubleshooting, plan/spec/contract set, and current-build screenshots for workbench, usage records, notifications, browser, command palette, and settings. | Video/GIF, fresh-user rehearsal, final public copy pass. |

## Matrix

### A. Workbench Automation

| ID | Human promise | Required implementation | Verification |
| --- | --- | --- | --- |
| A1 | A script can create a useful workspace from nothing. | CLI/socket methods for workspace create/select/rename/duplicate/close, surface split/focus/move/zoom/close, terminal send/key/text/cwd/title/rename, browser/file open, notifications, command execution, diagnostics, and graceful app quit. Existing channel-binding protocol remains a secondary ledger item, not an A1 completion dependency. | `Scripts/control-smoke.sh`; `Scripts/dogfood-workbench.sh` creates named workspaces with split terminals, browser tabs, attention events, screenshots, diagnostics, and relaunch checks. Real-agent dogfood remains. |
| A2 | Protocol and UI mutate the same model. | Router calls `ConductorWindowModel` methods only; no parallel hidden state. | Model tests and smoke script confirm UI state changes are visible in `workspace.list`/`surface.list`. |
| A3 | Commands fail politely. | Typed errors for app closed, target missing, disabled command, invalid params. | CLI returns non-zero and JSON error for bogus workspace/tab IDs. |
| A4 | Agents can ask for diagnostics. | `app.diagnostics` returns session, update, notification, workspace, surface, protocol state, and recent control errors; `app.diagnosticsExport` writes a redacted bundle. | `conductor diagnostics` includes journal summary and export smoke verifies manifest, summary output, and recent error reporting. |

### B. Session Life

| ID | Human promise | Required implementation | Verification |
| --- | --- | --- | --- |
| B1 | Relaunch restores the shape of work. | Compact snapshot persists workspace tree, selected content, terminal metadata, web tabs, file tabs, theme, appearance. | `dogfood-workbench.sh` opens browser and file tabs, creates unread events, gracefully quits and restarts the isolated app, then verifies `sessionRestore.state == restored`, selected workspace, web tab count, exact browser URL, browser page text after `browser.select`, restored browser scroll position, explicit back/forward fallback, terminal user title, terminal cwd, readable terminal output, restored-terminal `fresh-after-restore` process explanation, file tab count, unread count, and the restored file surface. Actual process reattach remains open. |
| B2 | A crash does not erase recent mutations. | Append-only session journal records semantic events and rotates safely. | Corrupt newest snapshot; recovery can inspect journal and explain fallback. |
| B3 | Terminal history is readable after restart. | Bounded VT/plain scrollback snapshots with no fake marker lines, replayed only after the fresh Ghostty surface is attached. | `dogfood-workbench.sh` sends real terminal commands, gracefully quits, relaunches, and verifies the target terminal's visible text contains the prior output. Broader colored-output/layout coverage remains open. |
| B4 | Agent sessions resume when supported. | Store sanitized agent session IDs/resume commands, cwd, terminal ID, and trust state; terminal context menu, command palette, `terminal.resumeAgent`, and `terminal.resumeAgents` can explicitly send canonical supported resume commands, with dry-run automation and fake-agent non-dry-run command delivery coverage. | Automatic launch-time resume is intentionally not done; real external-agent dogfood still needs to prove a resumed long conversation continues. |
| B5 | Browser tabs do not surprise-refresh. | Persist URL/title/favicon/error, explicit navigation entries/current index/scroll position, plus WebKit interaction state when available. | Dogfood verifies the restored current page can be selected and inspected after relaunch, restored scroll is above the fixture threshold, and `browser back`/`browser forward` move through the restored explicit history. No-reload WebKit restoration remains a known higher bar. |
| B6 | Restore failures are visible only when real. | Recovery summary with original/restored/dropped counts, missing file paths, corrupt file path, previous snapshot fallback, journal replay fallback, explicit restore-previous command, startup toast, and notification-panel event. | `dogfood-workbench.sh` first verifies normal relaunch reports `restored` without using previous fallback, then changes the current workspace, runs `session restore-previous`, verifies `restoredFromPrevious` and the previous selected workspace, then corrupts the current state file, relaunches, verifies `restoredFromPrevious`, verifies the missing file tab path is reported, and finds the `sessionRecovery` event. A separate isolated launch smoke verifies no compact snapshot plus a temporary journal reports `restoredFromJournal`, two workspaces, and one restored web tab. A dedicated no-toast visual assertion remains open. |

### C. Attention

| ID | Human promise | Required implementation | Verification |
| --- | --- | --- | --- |
| C1 | A sound is never the only evidence. | Durable in-app notification store independent of macOS banners, with panel and workspace chrome indicators. | Deny macOS notifications; event still appears in panel and workspace/sidebar/tab badges. |
| C2 | Notifications point somewhere. | Events include workspace ID, terminal/web target, source, timestamp, read state, and focus path. | Protocol focus by ID works in smoke; `CONDUCTOR_NOTIFICATION_AUTORUN=1` creates a terminal-targeted event, opens the panel, focuses the event, verifies unread clears, and confirms focus returns to the target terminal. |
| C3 | User knows permission state. | Settings and diagnostics show authorized, denied, not requested, unavailable, and unknown states; pure policy tests cover the decision matrix and debug-launch explanation. | Real `.app` automation still needs denied and authorized Notification Center states. |
| C4 | Agent/task completion is not duplicated endlessly. | Debounce per source/terminal while keeping diagnostics for suppressed duplicates. | Rapid repeated agent-hook events produce one visible event, a merged-count UI badge, and a tested suppression count; terminal desktop-notification escapes create in-app terminal alerts. |
| C5 | Keyboard/protocol paths work. | Jump latest unread, mark current workspace read, clear read/all. | `control-smoke.sh` verifies command-palette jump-latest prefers current-workspace unread items, falls back to the latest global unread item, focuses the target terminal/workspace, and marks events read; it also verifies command-palette mark-current-workspace-read. Broader shortcut binding coverage remains open. |

### D. Browser Surface

| ID | Human promise | Required implementation | Verification |
| --- | --- | --- | --- |
| D1 | Browser is a surface, not a demo. | Loading states, title/favicon cache, address/search, select existing/restored tab, explicit history, scroll restore, errors. | Manual local page flow, UI tests, and dogfood restored-tab selection/back/forward/scroll verification. |
| D2 | Agents can inspect pages. | `browser.snapshot` returns bounded text, links, fields, buttons, selection, frames where safe. | Local fixture snapshot matches expected text in `control-smoke.sh`; ref-specific assertions still need expansion. |
| D3 | Agents can act on pages. | `browser.click/fill/press/wait/find/evaluate/screenshot` live at basic DOM level, JS dialogs use native sheets, and WebKit downloads now persist state in the tab model. | Positive fixture form fill, press, click, wait, evaluate, find, screenshot, and binary download state scripts pass; frame/stress cases still need coverage. |
| D4 | Automation failures are actionable. | Typed errors for missing selectors, invalid selectors, missing snapshot refs, non-editable fill targets, missing text, script failure, unsupported Promise results, timeouts, missing frames, and inaccessible frames. Download failure state is user-visible and exported on browser surfaces; page console/error/unhandled-rejection events are captured as bounded runtime diagnostics; snapshot frame summaries explain whether frame content is accessible or blocked by origin/sandbox; cross-origin action routing still needs typed paths. | Negative fixture tests return typed JSON `automationError` details for the implemented cases, and control smoke verifies fixture console errors are visible in browser snapshot and surface metadata. It also verifies URL/title/idle/hidden/gone waits, a timed-out URL wait, same-origin frame text, same-origin frame fill/click/wait/find/evaluate routing, and inaccessible-frame reasons/errors. |
| D5 | Browser data is handled carefully. | No cookie/password dump in normal snapshots; storage/cookies only through explicit advanced commands. | Snapshot redaction tests. |

### E. Workspace Intelligence

| ID | Human promise | Required implementation | Verification |
| --- | --- | --- | --- |
| E1 | Sidebar and tabs answer "where am I?" fast. | Project name/path, terminals/web/files, running ports, local service summaries, unread state. `workspace.metadata` now provides the canonical snapshot plus tab-level terminal/file/web arrays; sidebar rows, the workspace inspector, and top workspace tabs show compact root/port/health/unread cues. | `control-smoke.sh` verifies selected and non-selected workspace terminal/file/web summaries against live fixtures, including a localhost server associated with the workspace. Screenshot review at compact and comfortable density remains. |
| E2 | Metadata does not slow terminals. | Port readers run off the main thread with bounded command timeouts; UI refresh still needs visibility-scoped debouncing. | Workspace switch and terminal scroll budgets stay under target. |
| E3 | Details are available without clutter. | Hover/detail popovers for paths, local services, ports, agents, notifications. | Hover audit checks every compact indicator has explanation. |
| E4 | Dev servers become useful links. | Detect ports from scoped process cwd and local web-tab context, expose URL/label/process metadata, and provide quick-open browser actions in the workspace inspector and top chrome. | `control-smoke.sh` starts a local fixture server, verifies `workspace.metadata.devServers` contains that URL/label, and the UI has service open actions wired to browser tabs. |

### F. Command and Shortcut Layer

| ID | Human promise | Required implementation | Verification |
| --- | --- | --- | --- |
| F1 | Every action is discoverable. | Canonical command registry with title, description, category, shortcut, enabled reason, protocol method. | `ConductorShellCommand` exposes registry metadata; command palette and `command.list` consume it; browser back/forward plus file external-open/reveal are now canonical commands and high-frequency toolbar/sidebar/web/file/search entries route through `performCommand`; full row-specific toolbar/sidebar/context action audit remains. |
| F2 | Shell panels do not leak shortcuts. | Modal/input containment blocks background workspace, tab, terminal shortcuts while allowing the visible panel's own close/toggle shortcut. | `CONDUCTOR_SHELL_PANEL_AUTORUN=1` opens settings, command palette, workspace overview, notifications, and terminal search, sends Cmd-T/Cmd-W/Cmd-D/Cmd-N/Cmd-K/Cmd-O/Cmd-F through the window, and verifies `shortcut-blocked=true` with no hidden workspace, tab, terminal, web, file, or panel mutation. |
| F3 | Shortcuts are user-owned. | Record/clear/default/conflict/reserved warning/import/export. | Recorder flow handles conflicts and reserved shortcuts; `CONDUCTOR_SHORTCUT_PROFILE_AUTORUN=1` verifies profile import/export, ignored unknown commands, rejected reserved shortcuts, conflict resolution, and valid exported entries. |
| F4 | Command palette feels native. | Outcome descriptions, disabled reasons, small shortcut badges, keyboard-only flow, recent command memory, and context-weighted ranking for web/file/terminal/attention/recovery states. | Palette opens within performance budget, runs expected command, and `control-smoke.sh` verifies metadata plus `ranking.recentRank == 0` after a command runs. |

### G. Native UX

| ID | Human promise | Required implementation | Verification |
| --- | --- | --- | --- |
| G1 | The app looks like one product. | Shared tokens for radius, spacing, elevation, opacity, motion, selection, focus. | Token audit and screenshots of settings, usage, notifications, command palette, toolbar. |
| G2 | Panels are usable at all sizes. | Internal scrolling, draggable/movable where expected, keyboard close, focus restoration. | Resize window and verify no unreachable controls. |
| G3 | Controls explain themselves. | Tooltips/help tags on every icon-only control, including shortcut hints. | Hover audit script/manual checklist. |
| G4 | Motion feels mac-native. | 100-180 ms bounded motion, reduced motion support, stable drag thresholds. | Click/drag tab test; no accidental drag on click. |
| G5 | Themes are real token sets. | At least ten readable tokenized themes with light/dark/glass/gradient/high contrast spread. | Theme screenshot matrix. |

### H. Updates and Distribution

| ID | Human promise | Required implementation | Verification |
| --- | --- | --- | --- |
| H1 | Update availability is obvious but quiet. | Top chrome update pill only for available/downloading/ready/failed states. | Simulated update states show correct pill and copy. |
| H2 | Download progress is believable. | Progress bar, bytes, speed when reliable, retry/cancel, background hourly check. | `Scripts/update-fixture.sh` now starts a delayed local update copy, polls `update.status`, verifies a visible progress sample before cancel, verifies the cancelled state is retryable, and then verifies at least two increasing `downloadProgress.fraction` samples before completion. Speed display and remote throttling coverage remain open. |
| H3 | Users do not see internals. | Normal UI hides manifest URLs, raw asset names, and architecture details unless diagnostics. | Settings/update screenshot review. |
| H4 | Replacement is safe. | SHA-256, bundle ID, signing/ad-hoc checks before install. | `Scripts/update-fixture.sh` now downloads a signed fixture `.app`, runs `update rehearse-install` to stage it, verifies the bundle identifier and strict codesign before replacement, and separately tampers with an asset to verify the app reports `failed` before install. Actual replacement/relaunch rehearsal remains open. |
| H5 | Releases are consistent. | arm64/x86_64 packages, checksums, manifest, release notes, real screenshots. | Release script validates all expected assets before upload. |

### I. Observability and QA

| ID | Human promise | Required implementation | Verification |
| --- | --- | --- | --- |
| I1 | One command answers "is it healthy?" | Diagnostics export writes redacted logs, app version, launch mode, update, notification, session, workspace/surface counts, control socket state, recent control errors, recent main-thread stalls, performance budget targets, recent budget samples, and a coverage/over-budget report. | `conductor diagnostics` and export command include core sections plus `performance.report`; `performance-gate.sh` enforces dogfood budget coverage and target status. |
| I2 | Regressions are caught before release. | Build/model/smoke/stress/browser/update/session scripts. | `Scripts/check-conductor.sh` now runs build, model check, optional full tests, isolated dogfood/control smoke, dogfood performance gate, protocol stress, update fixture, default autorun regressions, bundle build, and release screenshot capture. `Scripts/control-smoke.sh` verifies file open, text snapshot, direct save, reveal, targeted snapshot, typed file failure paths, and terminal scroll-frame budget diagnostics against a temporary local file/live terminal. `Scripts/stress-conductor.sh` verifies long output, resize while output, 20 idle terminals, 10 browser tabs, 10 browser automation iterations with same-origin frame fill/click/wait/find/evaluate, and rapid workspace switching; long-output now requires three visible split-terminal targets, 196,608 total characters, and three completion markers instead of accepting empty output. `Scripts/update-fixture.sh` passed available/download/progress/cancel/install-rehearsal/tamper plus `update.check` performance-gate coverage. The workspace autorun now verifies same-workspace and cross-workspace activation return to the terminal workbench after file-tab selection, shell-panel autorun verifies settings/command-palette/workspace-overview/notification/terminal-search shortcut containment, shortcut autorun verifies a valid `panes=3`/`terminals=3`/`zoomed=true` result, and notification autorun verifies store/show/jump/read/focus. A full unskipped gate run still needs to be completed before this row reaches L3. |
| I3 | Performance complaints are measurable. | Budget targets and samples for settings open, palette open, tab switch, scroll, web restore, update check. | Settings, palette, update check, terminal wheel scroll, and initial control-driven samples are recorded; diagnostics now summarizes sampled/missing budgets and recent over-budget samples; dogfood and update fixture gates enforce required sampled budgets and target status. |
| I4 | Screenshots are real. | Script captures current app screenshots for README/release notes with sensitive data masked. | `Scripts/capture-release-screenshots.sh` starts an isolated app, filters windows by PID/title, captures workbench, token records, notifications, browser, command palette, and settings, writes `docs/media/release-screenshots-manifest.json`, and masks account/path regions. |

### J. Documentation

| ID | Human promise | Required implementation | Verification |
| --- | --- | --- | --- |
| J1 | A stranger can install it. | README, getting started, Gatekeeper/ad-hoc signing explanation, requirements, update docs. | Fresh-user install rehearsal. |
| J2 | A stranger can operate it. | Workbench, workspace, browser, notification, command, shortcut, usage/update docs. | Docs cover the whole-day acceptance story. |
| J3 | A stranger can script it. | Local API docs, CLI examples, JSON envelope, error codes, security notes. | Examples run against debug app. |
| J4 | A stranger can troubleshoot it. | Notification, update, session restore, permissions, diagnostics bundle docs. | Every major failure state links to a doc section. |
| J5 | Public docs are honest. | Known limitations for ad-hoc signing, unsupported process restore, browser automation safety. | README does not overclaim L1 features as finished. |

## Dogfood Scenario

The release candidate must pass this scenario in one script plus one manual visual pass:

1. Start app with an isolated state path.
2. Create three workspaces: app, backend, release.
3. In each workspace, split two panes and send harmless commands that produce output.
4. Open one browser tab per workspace to a local fixture page.
5. Trigger one in-app notification per workspace and one macOS notification attempt.
6. Run browser snapshot/fill/click/screenshot on the fixture.
7. Export diagnostics.
8. Gracefully quit through the local protocol so terminal snapshots are captured.
9. Relaunch with the same state path.
10. Corrupt the current compact snapshot while keeping the previous snapshot, including one file tab whose target path is gone.
11. Relaunch and verify workspaces, panes, selected tabs, terminal title/cwd/readable output, browser URLs, restored browser page text after selecting the tab, file tabs, notification unread state, update state, and missing file paths restore or explain failures.

## Completion Rule

We can say "cmux-level useful" only when:

- All matrix rows are at least L2.
- Session life, attention, browser automation, updates, and diagnostics are L3.
- The delivery contract has no unaddressed required surface, failure-state, verification, or docs gaps.
- README and troubleshooting docs are based on real current screenshots.
- The whole-day acceptance story in the plan passes without hidden manual steps.
