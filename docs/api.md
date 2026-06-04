# Local Control API

Conductor exposes a user-local control API for scripts, tests, and agent workflows. It lets automation drive the same model as the UI: create workspaces, split panes, send text, open browser tabs, run commands, and create in-app attention events.

The API is local only. It uses a Unix domain socket in the current user's Application Support directory and never opens a remote network listener.

## Why It Matters

The control API turns Conductor from a window you must manually operate into a workbench that can be prepared and inspected by scripts.

Examples:

- Create a release workspace with two terminals and one docs tab.
- Send a command to the focused terminal.
- Open a browser tab to a project URL.
- Create an attention event when a background job finishes.
- Ask the app for diagnostics when a bug report arrives.

## CLI

From source builds, the CLI binary is:

```bash
Apps/Conductor/.build/debug/ConductorCLI
```

Build it:

```bash
cd Apps/Conductor
swift build --product ConductorCLI
```

With Conductor running:

```bash
.build/debug/ConductorCLI ping
.build/debug/ConductorCLI status
.build/debug/ConductorCLI diagnostics
.build/debug/ConductorCLI diagnostics export --output /tmp
```

## Transport

Default socket:

```text
~/Library/Application Support/Conductor/control.sock
```

For isolated tests:

```bash
CONDUCTOR_CONTROL_SOCKET_PATH=/tmp/conductor-control.sock
```

Requests and responses are newline-delimited JSON.

Request:

```json
{
  "id": "req-001",
  "method": "workspace.create",
  "params": {
    "title": "Release"
  },
  "client": {
    "name": "script",
    "version": "1"
  }
}
```

Success response:

```json
{
  "id": "req-001",
  "ok": true,
  "result": {
    "workspaceID": "..."
  }
}
```

Error response:

```json
{
  "id": "req-001",
  "ok": false,
  "error": {
    "code": "target_not_found",
    "message": "Workspace not found.",
    "details": {
      "workspaceID": "..."
    }
  }
}
```

## Implemented Commands

### App

```bash
.build/debug/ConductorCLI ping
.build/debug/ConductorCLI version
.build/debug/ConductorCLI status
.build/debug/ConductorCLI diagnostics
.build/debug/ConductorCLI diagnostics export --output ~/Desktop
.build/debug/ConductorCLI quit
```

### Session

```bash
.build/debug/ConductorCLI session inspect
.build/debug/ConductorCLI session restore-previous
```

`session inspect` returns the current recovery state, live workspace/surface
counts, restore-health report, recent session journal events, detected issues,
structured `surfaceIssues`, per-surface terminal/browser/file checks, severity
counts, target IDs, process status for restored terminals, user-impact text,
and a `primaryAction` object for each surface issue. The action object describes
the repair intent, label, icon, and whether the action is destructive, so UI and
scripts can explain the next click instead of only listing a raw diagnostic. Use
it first when a relaunch falls back, drops tabs, opens a fresh workspace, or
needs to explain that a terminal came back as a fresh process rather than a
reattached shell.

`session restore-previous` replaces the current workbench with the previous
valid compact snapshot. The current snapshot is preserved as the new previous
snapshot during the next save, so the command is a recovery action rather than a
one-way destructive reset. The response includes the same restore-health summary
used by `status` and `diagnostics`.

### AI Channels

```bash
.build/debug/ConductorCLI ai-channel list
.build/debug/ConductorCLI ai-channel configure local --name "Local Router" --kind openai-compatible --model qwen3-coder --endpoint http://127.0.0.1:11434/v1 --env OPENAI_API_KEY=...
.build/debug/ConductorCLI ai-channel set-default local
.build/debug/ConductorCLI ai-channel enable claude
.build/debug/ConductorCLI ai-channel disable gemini
.build/debug/ConductorCLI ai-channel set-priority local 120
.build/debug/ConductorCLI terminal channel get
.build/debug/ConductorCLI terminal channel set codex --model gpt-5
.build/debug/ConductorCLI terminal channel set claude --model sonnet --target <terminal-id>
.build/debug/ConductorCLI terminal channel set openai-compatible --endpoint http://127.0.0.1:11434/v1 --env OPENAI_BASE_URL=http://127.0.0.1:11434/v1
.build/debug/ConductorCLI terminal channel clear
```

AI channel support has two layers. `ai-channel list/configure/set-default`
manages the global channel catalog, including built-in presets, custom
OpenAI-compatible endpoints, enable/disable state, priority, default selection,
and health messages. `terminal channel set` stores a terminal-level override on
the selected terminal tab. `terminal channel clear` removes that override and
returns the terminal to global-default inheritance.

New Ghostty surfaces receive the effective binding for the terminal: the
terminal override when one exists, otherwise the global default channel. The
environment includes
`CONDUCTOR_AI_CHANNEL_ID`, `CONDUCTOR_AI_CHANNEL_KIND`, optional model/endpoint
values, and any validated environment keys attached to the binding.

If the terminal surface is already running, the command updates the persisted
tab binding but reports `requiresNewSurface: true`; Conductor does not silently
rewrite a live shell environment or contaminate other panes. Diagnostics and
`surface list` expose channel IDs, model names, endpoint strings, launch
arguments, inherited/effective bindings, and environment key names only, not
environment values.

`diagnostics export` writes a directory bundle and returns its path. The bundle
contains a redacted summary JSON, redacted diagnostic logs when available, a
manifest, and a short privacy note:

```json
{
  "path": "/Users/you/Desktop/conductor-diagnostics-20260603-120000",
  "fileCount": 4,
  "missingFiles": [],
  "files": [
    { "path": "README.txt", "bytes": 412 },
    { "path": "logs/diagnostics.log", "bytes": 2048 },
    { "path": "manifest.json", "bytes": 520 },
    { "path": "summary.redacted.json", "bytes": 4096 }
  ]
}
```

The export redacts the current home directory, `/Users/<name>` paths, and
email-like values. Review the directory before sharing it because project names
or command text can still appear in diagnostic events.

Diagnostics include `control.recentErrors`, a newest-first list of recent control
API failures with request ID, method, error code, message, timestamp, and bounded
details. This helps support distinguish an invalid command, a missing target,
and an app-side failure without asking the user to reproduce the issue first.

Diagnostics also include `performance.mainThread`, `performance.budgets`,
`performance.samples`, and `performance.report`.
`performance.mainThread.recentStalls` lists recent main-thread stalls captured by
the app watchdog with timestamp, duration, and threshold. `performance.budgets`
declares the current user-feel targets for settings open, command palette open,
workspace switching, terminal tab switching, terminal scrolling, update checks,
and browser restoration. Budget items include their latest sample when one has
been observed. `performance.samples.recent` is newest-first and records budget
ID, target, observed duration, pass/fail status, and source such as a control
protocol action, UI panel open, terminal scroll wheel/sample, or update check.
`performance.report` summarizes the recent sample window with sampled/missing
budget counts, missing budget IDs, recent over-budget samples, the slowest recent
sample, and an overall status such as `partial_coverage` or `recent_over_budget`.

### Workspace

```bash
.build/debug/ConductorCLI workspace list
.build/debug/ConductorCLI workspace metadata [--workspace workspace-id]
.build/debug/ConductorCLI workspace create --title "Release"
.build/debug/ConductorCLI workspace select <workspace-id>
.build/debug/ConductorCLI workspace rename "New Name"
.build/debug/ConductorCLI workspace duplicate
.build/debug/ConductorCLI workspace close
```

`workspace metadata` returns the selected workspace ID, workspace count, and a
workspace snapshot array. Each snapshot includes title, root path/source,
project name, terminal/browser/file counts, running ports when detected, local
dev-server summaries, active agent count, unread attention count, health, and
refresh time. It also returns `terminals`, `files`, and `webTabs` arrays with
tab-level IDs, titles, paths/URLs, selected state, loading/dirty state, and
agent hints when available. File and web tab arrays are workspace-owned, so a
non-selected workspace can still report its open content.
The command is intended for sidebar rows, workspace inspectors, and automated
dogfood checks that need to understand whether a workspace is alive before
opening a panel.

Local services are reported in `devServers` when they can be associated with the
workspace root or an open localhost web tab:

```json
{
  "devServers": [
    {
      "port": 5173,
      "url": "http://localhost:5173",
      "label": "Node :5173",
      "processID": 12345,
      "processName": "node",
      "workingDirectory": "/Users/you/project"
    }
  ]
}
```

This lets scripts and UI surfaces offer "open the running app" actions without
asking the user to remember which terminal started which local server.

### Surface And Terminal

```bash
.build/debug/ConductorCLI surface list
.build/debug/ConductorCLI surface split --direction right
.build/debug/ConductorCLI surface focus
.build/debug/ConductorCLI surface focus --web-tab <web-tab-id>
.build/debug/ConductorCLI surface focus --file-tab <file-tab-id>
.build/debug/ConductorCLI surface zoom
.build/debug/ConductorCLI surface move nextPane

.build/debug/ConductorCLI terminal cwd
.build/debug/ConductorCLI terminal title
.build/debug/ConductorCLI terminal agent
.build/debug/ConductorCLI terminal resume-agent [--dry-run]
.build/debug/ConductorCLI terminal rename "Release Runner"
.build/debug/ConductorCLI terminal send --text "npm test\n"
.build/debug/ConductorCLI terminal send-key enter
.build/debug/ConductorCLI terminal sample-scroll
.build/debug/ConductorCLI terminal visible-text
```

Browser rows in `surface list` include restore-oriented state for scripts and
diagnostics:

```json
{
  "type": "browser",
  "webTabID": "...",
  "url": "file:///...",
  "canGoBack": true,
  "canGoForward": false,
  "historyCount": 2,
  "historyIndex": 1,
  "scrollY": 951
}
```

`surface focus` can select terminal, browser, and file surfaces. Use
`--target <terminal-id>` for terminals, `--web-tab <web-tab-id>` for browser
tabs, and `--file-tab <file-tab-id>` for file tabs. Pair browser/file focus with
`--workspace <workspace-id>` when selecting a restored surface in another
workspace.

`terminal agent` returns the terminal's persisted agent snapshot. When a
supported hook provides a session ID, or the terminal output contains a clear
resume hint such as `codex resume <session-id>` or `claude --resume
<session-id>`, the response includes `agent.sessionIdentifier`,
`agent.resumeCommand`, and `agent.resumable: true`. `terminal resume-agent`
focuses that terminal and sends the canonical supported resume command. Use
`--dry-run` to verify what would be sent without launching the external agent.
Conductor exposes this state for recovery and explicit UI actions, but it does
not execute resume commands automatically.

### Browser

```bash
.build/debug/ConductorCLI browser open "https://duckduckgo.com/?q=swiftui"
.build/debug/ConductorCLI browser select <web-tab-id> [--workspace workspace-id]
.build/debug/ConductorCLI browser navigate "https://example.com"
.build/debug/ConductorCLI browser reload
.build/debug/ConductorCLI browser stop
.build/debug/ConductorCLI browser back
.build/debug/ConductorCLI browser forward
.build/debug/ConductorCLI browser snapshot
.build/debug/ConductorCLI browser screenshot
.build/debug/ConductorCLI browser click link-0
.build/debug/ConductorCLI browser fill field-0 "swiftui"
.build/debug/ConductorCLI browser press Enter --element field-0
.build/debug/ConductorCLI browser wait load --timeout 10
.build/debug/ConductorCLI browser wait idle --timeout 10
.build/debug/ConductorCLI browser wait "#ready"
.build/debug/ConductorCLI browser wait text "Done"
.build/debug/ConductorCLI browser wait url "localhost:5173"
.build/debug/ConductorCLI browser wait title "Preview"
.build/debug/ConductorCLI browser wait hidden "#spinner"
.build/debug/ConductorCLI browser wait gone "#toast"
.build/debug/ConductorCLI browser find "Release notes" [--frame frame-0]
.build/debug/ConductorCLI browser evaluate "document.title"
.build/debug/ConductorCLI browser evaluate --frame frame-0 "document.body.innerText"
```

`browser select` makes an existing web tab the active browser surface. It can
select a tab in the current workspace, or use `--workspace <workspace-id>` to
jump to a restored tab in another workspace before running snapshot, wait,
back/forward, or DOM automation commands.

Browser tabs persist an explicit navigation list and scroll position in addition
to WebKit's opaque interaction state. After relaunch, `browser back` and
`browser forward` use WebKit history when available and fall back to the explicit
history when WebKit returns an inconsistent restored list.

`browser snapshot` returns bounded page data from the currently selected web tab
or `--target <web-tab-id>`:

```json
{
  "webTabID": "...",
  "title": "Example",
  "url": "https://example.com/",
  "text": "Visible page text...",
  "selectedText": "",
  "links": [{ "id": "link-0", "text": "Docs", "href": "https://example.com/docs" }],
  "fields": [{ "id": "field-0", "tag": "input", "type": "search", "label": "Search" }],
  "buttons": [{ "id": "button-0", "text": "Submit" }],
  "frames": [
    {
      "id": "frame-0",
      "title": "Embedded Preview",
      "source": "http://localhost:5173/preview",
      "accessible": true,
      "sameOrigin": true,
      "visible": true,
      "text": "Preview text...",
      "linkCount": 2,
      "fieldCount": 1,
      "buttonCount": 1,
      "reason": ""
    },
    {
      "id": "frame-1",
      "title": "External",
      "source": "https://example.org/",
      "accessible": false,
      "sameOrigin": false,
      "visible": true,
      "text": "",
      "reason": "Frame content is not accessible from the main page origin."
    }
  ]
}
```

`browser screenshot` writes a visible-viewport PNG to a temporary Conductor browser screenshot directory and returns the file path:

```json
{
  "webTabID": "...",
  "title": "Example",
  "url": "https://example.com/",
  "path": "/var/folders/.../Conductor/BrowserScreenshots/browser-....png",
  "width": 1512,
  "height": 982,
  "scale": 2
}
```

`browser click`, `browser fill`, `browser press`, and `browser wait` accept
snapshot refs such as `link-0`, `button-0`, and `field-0`, or a CSS selector for
advanced scripts. `browser wait` supports `load`, `ready`, `idle`,
`networkidle`, selector/visible, `text`, `url`, `title`, `hidden`, and
`gone`/`detached` conditions with a bounded timeout. `browser find` returns a
bounded match count and searches the main document plus accessible same-origin
frames. `browser evaluate` runs trusted JavaScript against the visible tab and
returns a bounded serialized result:

```json
{
  "webTabID": "...",
  "action": "fill",
  "target": "field-0",
  "matched": true,
  "message": "Filled Search.",
  "text": "",
  "value": "swiftui",
  "url": "https://example.com/"
}
```

For same-origin frames, use the frame ID from `browser snapshot`:

```bash
.build/debug/ConductorCLI browser fill "frame-0 >> #query" "release notes"
.build/debug/ConductorCLI browser click "frame-0 >> #search"
.build/debug/ConductorCLI browser wait text "frame-0 >> Search complete"
.build/debug/ConductorCLI browser find --frame frame-0 "Search complete"
.build/debug/ConductorCLI browser evaluate --frame frame-0 "document.title"
```

Frame commands intentionally respect browser origin boundaries. If a frame is
sandboxed or cross-origin, Conductor reports the frame in `browser snapshot` with
an inaccessible reason and returns a typed automation error when a script tries
to act inside it.

Normal snapshots do not dump cookies, local storage, or password values. Basic
DOM automation, bounded waiting, dialog handling, download state, same-origin
frame automation, runtime-event diagnostics, local fixture smoke, and browser
automation stress coverage are available. Cross-origin action routing, longer
duration browser stress, user-facing automation error UI, and stronger
JavaScript bridge hardening remain open.

When browser automation fails, the API returns the normal error envelope with
`error.details.automationError` for common cases:

- `selector_not_found`: a CSS selector did not match an element.
- `invalid_selector`: a CSS selector could not be parsed.
- `snapshot_ref_missing`: a snapshot ref such as `button-42` no longer exists.
- `not_editable`: `browser fill` targeted an element that cannot accept text.
- `text_not_found`: `browser find` could not find visible matching text.
- `script_error`: `browser evaluate` threw in the page.
- `promise_unsupported`: `browser evaluate` returned a Promise; async evaluation is not enabled yet.
- `timeout`: `browser wait` did not match before the bounded timeout.
- `missing_url`: a URL wait was called without a URL fragment.
- `missing_title`: a title wait was called without a title fragment.
- `frame_not_found`: a frame target such as `frame-9` no longer exists.
- `frame_inaccessible`: the target frame is unavailable, sandboxed, or blocked by browser origin rules.

### Notifications

```bash
.build/debug/ConductorCLI notify "Build finished" --body "npm test passed"
.build/debug/ConductorCLI notify "Agent finished" --workspace <workspace-id> --terminal <terminal-id>
.build/debug/ConductorCLI notify list
.build/debug/ConductorCLI notify focus <notification-id>
.build/debug/ConductorCLI notify latest
.build/debug/ConductorCLI notify mark-read [--workspace workspace-id]
.build/debug/ConductorCLI notify clear <notification-id>
.build/debug/ConductorCLI notify clear
.build/debug/ConductorCLI notify test [--title title] [--body text] [--silent]
```

Notifications created through the API are stored in the in-app attention store and can be focused, jumped to by newest unread, marked read, or cleared by ID. Creation accepts optional workspace, terminal, and web-tab IDs so scripted jobs can create events that return the user to the exact surface that needs attention.
`notify latest` mirrors the command-palette "Jump to Latest Unread" action: it prefers the selected workspace's unread event when one exists, then falls back to the newest unread event globally.
Background terminal command completion is also exposed through this same store as `kind: commandFinished` with `source: terminal-command` when a non-agent command fails or a long-running command finishes while unattended.
For terminal attention events, macOS banners are a delivery layer on top of the store. Scripts should treat `notify list` as the source of truth and use `diagnostics.notifications` to inspect whether the current launch can show system banners.
`notify test` calls `notification.test` and returns `status`, `authorization`, `launchSupportsSystemNotifications`, `addedToNotificationCenter`, and `error`; use it when you need to know whether macOS Notification Center accepted a test banner.

### Updates

```bash
.build/debug/ConductorCLI update status
.build/debug/ConductorCLI update check [--manifest url-or-path] [--timeout seconds]
.build/debug/ConductorCLI update download [--timeout seconds]
.build/debug/ConductorCLI update cancel
.build/debug/ConductorCLI update rehearse-install
.build/debug/ConductorCLI update install
```

`update check --manifest` is intended for tests and maintainer diagnostics. It uses the supplied manifest for the running app session without saving that URL into user settings. `update download` waits until the download settles and returns the final update state, including `downloadedPackagePath` on success or `phase: failed` for verification errors such as checksum mismatch. `update cancel` stops an active check/download and returns the current update state; when cancelling a download with a known manifest it should return `phase: available` and `canDownload: true` so the user can retry. `update rehearse-install` runs the installer in dry-run mode after a verified download; it stages the app, checks the bundle identifier, and runs strict codesign verification without replacing the current app. Update responses include `automaticChecks` with the enabled/running state, next scheduled check, last attempt/completion, consecutive background failures, and the last background failure description for diagnostics.

### Files

```bash
.build/debug/ConductorCLI file open <path> [--root path]
.build/debug/ConductorCLI file reveal [path] [--root path]
.build/debug/ConductorCLI file save [target] [--text text|--stdin]
.build/debug/ConductorCLI file snapshot [--target selected|path|file-tab-id] [--text] [--max-text-bytes bytes]
```

`file.open` opens a real file in the workspace tab strip. `file.reveal` opens Conductor's file manager panel at a directory or selected file. `file.snapshot` returns open file tabs, selected state, metadata, dirty/external-change flags, synchronized editor-buffer state, and bounded text when `--text` is supplied. `file.save --text` writes the supplied content to a target path and updates any matching open editor buffer. Without text, `file.save` writes the synchronized editor buffer for the open file tab and returns `mode: buffered-editor-save` plus the saved buffer revision.

File commands return typed errors for common failure states, including
`file_not_found`, `file_is_directory`, `file_parent_not_found`,
`file_not_writable`, `file_too_large`, `file_write_failed`, and
`file_buffer_unavailable`. Path-based errors include `error.details.path` so
diagnostics and scripts can show the exact filesystem target.

### Commands

```bash
.build/debug/ConductorCLI command list
.build/debug/ConductorCLI command run <command-id>
```

`command list` returns the same canonical command metadata used by the command
palette: command ID, catalog ID, category, title, user-facing description,
keywords, SF Symbol name, protocol method, enabled state, disabled reason, and
resolved shortcut. It also returns the command palette ranking model with a
score, recent-use state, context reasons, and the small badge shown in the UI.
This lets scripts build their own quick menus without duplicating Conductor's UI
rules.

Example command item:

```json
{
  "id": "splitRight",
  "catalogID": "split-right",
  "category": "Create",
  "title": "Split Right",
  "description": "Creates a new terminal pane to the right of the current pane.",
  "keywords": "split right vertical",
  "systemImage": "rectangle.split.2x1",
  "protocolMethod": "command.run",
  "enabled": true,
  "disabledReason": null,
  "shortcut": "Cmd-D",
  "ranking": {
    "score": 1120,
    "recent": false,
    "recentRank": null,
    "contextual": true,
    "contextReasons": ["Current Terminal"],
    "badge": "Current Terminal"
  }
}
```

When a command cannot run, `command run` returns `command_disabled` with
`error.details.disabledReason`, so UI and automation can show the same reason as
the command palette.

## Error Codes

Common codes:

- `invalid_params`: required input is missing or malformed.
- `target_not_found`: workspace, terminal, web tab, or notification ID no longer exists.
- `command_disabled`: command exists but cannot run in the current context.
- `internal_error`: app-side operation failed unexpectedly.

Browser automation commands may also include `error.details.automationError`
with one of the browser-specific codes listed above.

If the app is not running or the socket is stale, the CLI exits with an app-not-running message.

## Smoke Test

```bash
cd Apps/Conductor
./Scripts/control-smoke.sh
```

The smoke script checks:

- app ping/status/diagnostics/diagnostics export/version
- workspace create/rename/list
- surface split/zoom/focus
- terminal cwd/title/agent/rename/send/send-key/sample-scroll/visible-text
- browser open/reload/stop against a local fixture
- browser snapshot/screenshot/click/fill/press/wait/find/evaluate, including
  advanced wait states, runtime-error diagnostics, downloads, same-origin frame
  snapshots, frame actions, frame-local find/evaluate, and inaccessible-frame
  error paths
- dogfood browser relaunch restore for URL, page text, scroll position, and explicit back/forward fallback
- dogfood terminal relaunch restore for user title, cwd, and readable visible output
- dogfood agent resume-command capture and relaunch persistence for restored terminals
- dogfood `session inspect` restore verification that focuses restored terminal, browser, and file surfaces
- dogfood restored-terminal process explanation: `process.status == fresh-after-restore` plus a `terminal_process_restarted` surface issue
- workspace metadata for the selected workspace, including counts and health
- file open/snapshot/save/reveal against a temporary local file, plus typed file failure paths
- command list
- notification create/list/focus/clear

`./Scripts/check-conductor.sh` also runs `./Scripts/performance-gate.sh` against
the dogfood diagnostics bundle. By default it requires sampled budgets for
workspace switching, terminal tab switching, terminal scroll frames, browser
restore, settings open, and command palette open, and fails if any enforced
budget is over target. Use `CONDUCTOR_CHECK_SKIP_PERF_GATE=1` only for local
triage when performance data is intentionally noisy.

`./Scripts/stress-conductor.sh` covers long terminal output, resize while output,
20 idle terminals, 10 browser tabs, rapid workspace switching, and 10 browser
automation iterations where each browser tab runs same-origin frame
fill/click/wait/find/evaluate.

Use `CONDUCTOR_SMOKE_SKIP_CLI_BUILD=1` after the CLI is already built to avoid repeated SwiftPM manifest evaluation.

## Security Notes

- The API is local to the current user.
- There is no HTTP server and no remote listener.
- The socket path can be overridden for isolated testing.
- The API does not expose browser cookies, passwords, or token data.
- Diagnostics export redacts common personal fields, but bundles should still be reviewed before sharing publicly.
