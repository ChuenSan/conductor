# Session Restore

Conductor is designed to preserve the shape of a work session: workspaces, terminal panes, selected tabs, web tabs, file tabs, appearance, and useful terminal snapshots.

Session restore is not the same as process reattachment. If a shell process exits while the app is closed, Conductor can restore layout and saved context, but it may not be able to revive the original process.

## What Restores Today

Current persisted state includes:

- workspace list
- selected workspace
- terminal pane layout
- selected terminal/content tab
- terminal titles and IDs
- sidecar terminal scrollback snapshots
- web tab records
- file tab records
- appearance and theme settings
- in-app attention events

State is written to:

```text
~/Library/Application Support/Conductor/window-state.yaml
```

The previous valid compact snapshot is retained at:

```text
~/Library/Application Support/Conductor/window-state.previous.yaml
```

Legacy state may be read from:

```text
~/Library/Application Support/Conductor/window-state.json
```

## Session Journal

Conductor also writes an append-only session journal:

```text
~/Library/Application Support/Conductor/session-journal.ndjson
```

The journal records semantic events such as workspace creation, rename, close, selected workspace changes, terminal creation/close, browser tab open/navigate/close, file tab open/close, and snapshot saves.

Implemented:

- append-only journal
- journal rotation
- string ID encoding with legacy ID decode support
- diagnostics summary through `app.diagnostics`
- session health inspection through Settings > Overview and `ConductorCLI session inspect`
- previous valid snapshot fallback when the latest compact snapshot cannot restore
- journal replay fallback when compact snapshots are missing or invalid; it rebuilds a session skeleton from semantic events and reports `restoredFromJournal`
- explicit "Restore Previous Session" through command palette, `session.restorePrevious`, and `ConductorCLI session restore-previous`
- restore-health diagnostics for source path, attempted paths, failed paths, original/restored/dropped counts, and missing file paths
- in-app recovery notification and startup toast when fallback or failure happens, including the first missing file name when file tabs were dropped
- ordinary relaunch dogfood coverage for terminal title, cwd, readable terminal output, browser URL, browser page text, explicit browser back/forward fallback, browser scroll position, file tabs, and unread attention state
- supported-agent resume metadata capture when hooks provide a session ID or terminal output prints a clear `codex resume <session-id>` / `claude --resume <session-id>` hint
- explicit supported-agent resume through the terminal tab context menu and `ConductorCLI terminal resume-agent`; `--dry-run` verifies the command without starting the external agent
- current-workspace supported-agent batch resume through the command palette and `ConductorCLI terminal resume-agents --workspace current|all|<workspace-id>`; `--dry-run` lists targets and canonical commands without starting external agents, and release dogfood executes the non-dry-run path against a local fake supported-agent binary so the command-sending path is verified without network or token use
- restored supported-agent terminals explain their process boundary in Settings > Overview and `session inspect`: Conductor can restore context and readable output, but reports `fresh-after-restore` when the original shell or agent process was not reattached

Still in progress:

- no-reload WebKit restoration
- process reattachment and real external-agent continuation dogfood

## Terminal Snapshots

Conductor stores bounded terminal sidecar snapshots under:

```text
~/Library/Application Support/Conductor/session-snapshots/
```

Snapshots are intended to preserve useful recent context, not infinite terminal history. They should not inject fake marker lines into restored output.

Snapshots are captured during graceful app shutdown and replayed only after the
fresh terminal surface is attached. Replay uses the program-output path, not the
shell input path, so restored text is visible context rather than a command that
gets executed.

## Browser Restore

Conductor stores web tab metadata, explicit navigation entries, scroll position,
and WebKit interaction state when available. The goal is to restore the last
useful browser context without surprise reload loops.

Current browser restore can fall back to explicit history when WebKit rejects or
misorders a saved interaction state. True no-reload WebKit restoration is still
being hardened.

## Restore Previous Session

Open Settings > Overview to see the compact session health card. It shows the
latest restore state, recovered workspace/web/file counts, journal entry count,
terminal/browser/file surface counts, structured surface issue counts, detected
issues, recent semantic journal events, and a disabled/enabled "Restore
Previous" action. When a surface needs attention, the recovery check lists the
affected terminal, browser, or file with severity, a human-readable reason, and
the next action the user can take.
Clicking one of those rows switches to the affected workspace and selects the
terminal, browser tab, or file tab.

For deeper recovery inspection, use:

```bash
cd Apps/Conductor
.build/debug/ConductorCLI session inspect
```

The top-level `surfaceIssues` field and `surfaces.issues` field list structured
recovery checks with severity, surface kind, workspace ID, optional terminal/web
/file target IDs, a readable title/detail, and a suggested action. The
`surfaces` field still lists every workspace with terminal, browser, and file
checks. Terminal checks include title, working directory, focus/selection, agent
resume metadata, last command, search state, process status, and issues such as
missing working directory, missing agent resume metadata, or
`terminal_process_restarted`. `terminal_process_restarted` is informational: it
means Conductor restored terminal context, but the original process was not
reattached. Browser checks include URL, explicit history count/index,
back/forward capability, scroll position, interaction-state availability, load
errors, and blank/history/scroll issues. File checks include path, root,
dirty/external-change state, existence, and missing-file issues.

Use `ConductorCLI terminal agent [--target <terminal-id>]` to read the same
agent snapshot for one terminal. When `agent.resumable` is true, Conductor has
stored a session ID and a resume command, but it still leaves execution to the
user or an explicit future UI action.
In the UI, terminal tab hover text shows a captured resume command, the terminal
tab context menu can copy it, and Settings > Overview lists resumable terminals
with jump and copy actions.
For a restored workspace with several supported agents, use the command palette
action "Resume Workspace Agents" or:

```bash
cd Apps/Conductor
.build/debug/ConductorCLI terminal resume-agents --workspace current --dry-run
```

Remove `--dry-run` to send each canonical resume command back to its matching
terminal. This is intentionally explicit rather than automatic on launch, so a
restart does not unexpectedly start external agents or spend tokens.

Scripts can jump directly to those surfaces with `surface focus --target
<terminal-id>`, `surface focus --web-tab <web-tab-id>`, or `surface focus
--file-tab <file-tab-id>`.
The dogfood recovery path exercises this after a normal relaunch: it reads the
restored terminal, browser, and file IDs from `session inspect`, focuses each
surface, and verifies the focus response points back to the restored release
workspace.

If a newer session is wrong but the previous compact snapshot is still available,
use:

```bash
cd Apps/Conductor
.build/debug/ConductorCLI session restore-previous
```

The same action is available from the command palette as "Restore Previous
Session". It replaces the current in-memory workbench with the previous valid
snapshot and shows the normal recovery toast/event. The current snapshot is
preserved as the new previous snapshot on the next save, so this is a recoverable
operation rather than a blind reset.

## Isolated Restore Testing

Use `CONDUCTOR_STATE_PATH` to test restore behavior without touching your real state:

```bash
cd Apps/Conductor
CONDUCTOR_STATE_PATH=/tmp/conductor-restore/window-state.yaml \
./Scripts/run-conductor.sh
```

For control API dogfood tests, combine it with a temporary socket:

```bash
CONDUCTOR_STATE_PATH=/tmp/conductor-restore/window-state.yaml \
CONDUCTOR_CONTROL_SOCKET_PATH=/tmp/conductor-restore/control.sock \
.build/debug/Conductor
```

The release dogfood script now includes normal restore and restore-fallback
checks. The normal path creates a multi-workspace session with split terminals,
browser tabs, file tabs, and attention events, gracefully quits, relaunches, and
verifies `sessionRestore.state == restored`, selected workspace, terminal
title/cwd/readable output, browser URL/page text/scroll/back/forward, file tabs,
unread state, restored agent resume metadata, and a real non-dry-run resume
send through a local fake supported-agent binary. It then switches to another workspace, runs `session
restore-previous`, and verifies the previous selected workspace returns. The
fallback path injects a file tab whose target disappears, corrupts the current
state file, relaunches, verifies `sessionRestore.state == restoredFromPrevious`,
confirms the missing file path is reported, and confirms an in-app
`sessionRecovery` event was created. This proves the user sees what was restored
and what was dropped instead of silently landing in a blank workspace.

## Diagnostics

```bash
cd Apps/Conductor
.build/debug/ConductorCLI session inspect
.build/debug/ConductorCLI diagnostics
```

Useful fields:

- session inspect state and recommended actions
- session journal path
- event count
- latest journal event
- session restore state
- attempted and failed state paths
- original, restored, and dropped workspace/web/file counts
- missing file tab paths
- attention store path
- unread attention count
- workspace count
- surface count
- structured surface issue count, severity, affected surface, and suggested action
- control socket path

## Expected Failure Handling

Conductor should explain these cases:

- latest state file is unreadable, with fallback to the previous valid snapshot when available
- journal contains corrupt lines
- previous snapshot is missing
- terminal process cannot be reattached
- browser interaction state is invalid
- file tab path no longer exists

The app should not silently open a blank workspace unless no usable state remains.

## Current Limits

- Journal replay is not complete yet.
- Terminal process reattachment is not complete yet; restored terminals with
  useful runtime context report `fresh-after-restore` so this limit is visible.
- No-reload WebKit restoration and automatic supported-agent resume are not complete yet.
- Recovery fallback/failure is visible through a startup toast, notification
  panel event, Settings > Overview recovery check, and `session inspect`.
