# cmux-Level Workbench: Product and Engineering Design

- **Date:** 2026-06-03
- **Status:** Draft for full implementation; Track A foundation implemented
- **Scope:** Full Conductor maturity pass: protocol, session, attention, browser, workspace intelligence, native UX, updater, QA, docs
- **Plan:** `docs/superpowers/plans/2026-06-03-cmux-level-workbench.md`
- **Capability matrix:** `docs/superpowers/specs/2026-06-03-cmux-level-capability-matrix.md`
- **Delivery contract:** `docs/superpowers/specs/2026-06-03-cmux-level-delivery-contract.md`

## 1. Thesis

Conductor should become a calm macOS workbench for terminal-heavy agent work.

The target is not "more UI" and not a full IDE. The target is trust. A user should feel
that Conductor can hold a day of work: terminals keep their identity, browser tabs keep
their context, notifications point somewhere real, and every button/action makes sense.

The reference bar is cmux-level usefulness: scriptable workspace primitives, strong
terminal integration, browser surfaces that can be driven, and attention states that help
humans coordinate multiple agents. We do not copy implementation or visual style. We build
the Conductor-native version around Swift/AppKit/WebKit/GhosttyKit.

## 2. Product Principles

### 2.1 Calm density

Conductor should show important state without becoming a dashboard. Project, ports,
agent, unread, and update states belong in compact chrome and hover details. Big
cards are reserved for repeated content or true focused panels, not for every metric.

### 2.2 Actionable attention

A notification is not "a sound happened." A notification is a navigable event with a
workspace, surface, timestamp, read state, and focus action. If macOS cannot show a banner,
the in-app attention system still works and explains permission state.

### 2.3 Scriptable by default

Any important UI action should have a protocol equivalent: create workspace, split pane,
send text, open browser, inspect browser, create notification, run command, check update.
This lets humans write scripts and lets agents operate the workbench without fragile UI
clicking.

### 2.4 Restore or explain

State may fail to restore because a file disappeared, a WebKit state blob is invalid, or a
terminal process is gone. The app may not silently pretend everything is fine. Restore what
can be restored and summarize what was dropped.

### 2.5 Native first

Conductor should feel like a macOS tool: crisp hover help, normal focus rings, restrained
motion, small settings, scrollable panels, sensible traffic-light spacing, and clean
toolbar groups. Avoid vague AI phrases and decorative glow.

## 3. Whole-Day User Journey

### Morning restore

The user launches Conductor. The app restores last night:

- Three workspaces.
- The selected workspace and selected terminal tab.
- Browser tabs with their last URL/history where available.
- File tabs and dirty/external-change state.
- Notifications from unfinished tasks.
- Update state if an update was already downloaded or failed.

The user can answer, without opening settings:

- Which workspace am I in?
- What project path is this?
- Are there unread agent replies?
- Is anything running locally?

### Starting work

The user opens command palette or runs CLI:

```bash
conductor workspace create --title "Release"
conductor surface split --direction right
conductor terminal send --text "npm test\n"
conductor browser open "https://github.com"
```

The UI updates exactly as if the user clicked the controls. There is no parallel model for
CLI vs UI behavior.

### Running several agents

The user starts multiple CLI agents in different panes. Conductor records:

- Terminal ID.
- Workspace ID.
- Active agent/provider.
- CWD.
- Last command summary.
- Last reply notification.
- Whether the user has read the event.

When agents finish, the app marks the relevant workspace and terminal unread, posts an
in-app event, and optionally posts a macOS banner.

### Returning after leaving

The user comes back. The sidebar/top chrome tells where attention is needed. The user can:

- Click the unread badge.
- Run "Jump to latest unread".
- Open the notification panel.

All paths focus the same target: workspace, surface, terminal tab, and the notification
event that caused the state.

### Failure and recovery

If the app crashes or is force-quit, state is recovered from the latest compact snapshot
plus session journal. If a terminal process cannot be reattached, its restored terminal
shows a clear "process ended before restore" state with preserved scrollback snapshot.

### Update

If a GitHub release has a newer build, the toolbar shows a small update pill. The update
panel says "Update available", "Downloading", "Ready to install", or "Failed". It never
shows raw manifest URLs in normal UI.

## 4. Information Architecture

### 4.1 Main window regions

```text
Window
├── sidebar
│   ├── workspace switcher
│   ├── compact workspace rows
│   └── bottom utility icons
├── top chrome
│   ├── workspace/content tab strip
│   ├── update pill
│   └── action clusters
├── content surface
│   ├── terminal split tree
│   ├── web tab surface
│   ├── file/document surface
│   └── native preview surface
└── overlay panels
    ├── command palette
    ├── notification panel
    ├── settings panel
    ├── usage panel
    └── workspace inspector
```

### 4.2 Sidebar row content

Each workspace row should fit one compact row plus optional hover detail.

Visible row:

- Workspace title.
- Terminal count and web/file count when non-zero.
- Short path or project name.
- One unread badge if needed.
- One status dot only when meaningful: active agent, error, update, or waiting.

Hover/detail:

- Full path.
- Running ports.
- Active agent terminal titles.
- Last notification time.

Do not show every metric all the time. Orientation first; detail on demand.

### 4.3 Top chrome

Toolbar groups should be compact and consistent:

- New menu.
- Split controls.
- File/workspace controls.
- Notifications.
- Command palette.
- Update pill when relevant.

Every icon-only button must have a tooltip with action and shortcut when available.

### 4.4 Panels

Panels must be movable when modeless and must have internal scrolling when content exceeds
available height. No panel should require resizing the whole app to reach controls.

Settings is a navigation panel, not a dashboard. The left sidebar is section navigation.
The right side is dense but readable grouped controls. Large cards are allowed only for
individual repeated items or focused inspector blocks.

## 5. Control Protocol

### 5.1 Transport

Use a user-local Unix domain socket:

```text
~/Library/Application Support/Conductor/control.sock
```

The socket server accepts newline-delimited JSON. It never listens on a network interface.
Requests include an ID; responses include the same ID.

### 5.2 Envelope

```json
{
  "id": "req-001",
  "method": "workspace.list",
  "params": {},
  "client": {
    "name": "conductor-cli",
    "version": "0.0.1"
  }
}
```

Response:

```json
{
  "id": "req-001",
  "ok": true,
  "result": {
    "workspaces": []
  }
}
```

Error:

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

### 5.3 Method families

| Family | Methods |
| --- | --- |
| App | `app.ping`, `app.version`, `app.status`, `app.diagnostics` |
| Workspace | `workspace.list`, `workspace.create`, `workspace.select`, `workspace.rename`, `workspace.duplicate`, `workspace.close` |
| Surface | `surface.list`, `surface.focus`, `surface.split`, `surface.move`, `surface.zoom`, `surface.close` |
| Terminal | `terminal.sendText`, `terminal.sendKey`, `terminal.visibleText`, `terminal.cwd`, `terminal.title`, `terminal.sampleScroll`, `terminal.rename` |
| Browser | `browser.open`, `browser.navigate`, `browser.snapshot`, `browser.screenshot`, `browser.click`, `browser.fill`, `browser.press`, `browser.evaluate`, `browser.find` |
| File | `file.open`, `file.reveal`, `file.save`, `file.snapshot` |
| Notification | `notification.create`, `notification.list`, `notification.markRead`, `notification.clear`, `notification.focusLatest` |
| Update | `update.check`, `update.download`, `update.install`, `update.status` |
| Command | `command.list`, `command.run` |

**2026-06-03 implementation status:** The first control layer is live: local socket
server, JSON router, CLI, app/workspace/surface/terminal/browser navigation methods,
notification create/list/focus/clear backed by the in-app attention store, command
list/run, protocol tests, and socket smoke coverage. `CONDUCTOR_CONTROL_SOCKET_PATH`
allows isolated smoke runs without touching the user's live app. Browser
snapshot/click/fill/screenshot are still Track D.

### 5.4 CLI shape

CLI should be friendly enough for humans and stable enough for scripts.

```bash
conductor status
conductor workspace list --json
conductor workspace create --title "Release" --cwd ~/project
conductor workspace select <workspace-id>
conductor surface split --direction right
conductor terminal send --target focused --text "npm test\n"
conductor browser open "https://duckduckgo.com/?q=swiftui"
conductor browser snapshot --target current --json
conductor notify "Build finished" --body "npm test passed"
conductor update check
```

### 5.5 Protocol acceptance

- UI actions and CLI actions mutate the same `ConductorWindowModel` path.
- Invalid IDs never crash; they return typed errors.
- The app can be closed; CLI reports "app_not_running".
- Smoke tests can drive the app without AppleScript or mouse automation.

## 6. Session Model

### 6.1 State layers

```text
Compact snapshot
├── workspaces
├── selected workspace/content
├── terminal metadata
├── browser metadata
├── file tabs
├── notifications
├── settings
└── update state

Session journal
├── append-only events
├── last N minutes/hours of workspace mutations
└── recovery fallback for partial writes

Surface runtime
├── Ghostty surfaces
├── WKWebViews
└── AppKit views
```

Snapshot should be compact and stable. Runtime objects do not go into SwiftUI state.

**2026-06-03 implementation status:** The compact snapshot remains authoritative. A
bounded append-only journal now records snapshot saves plus semantic workspace, terminal,
browser, and file-tab mutations. `app.diagnostics` exposes the journal count, file size,
latest event, and current restore-health placeholder so recovery work can be verified
without opening raw state files. The next step is journal replay and previous-snapshot
fallback.

### 6.2 Terminal restore

Persist:

- Terminal ID.
- Pane/workspace ID.
- Title.
- CWD.
- Last known command summary.
- Active agent title/state.
- Search metadata.
- Scrollback snapshot.
- Readonly/restored-ended flag.

If live process reattach is not implemented yet, restored terminal history should still be
readable and clearly marked when the process is no longer running. Do not inject fake
marker lines into terminal output.

### 6.3 Browser restore

Persist:

- Web tab ID.
- Last URL.
- Title.
- Pending address.
- Favicon URL.
- Interaction state blob when available.
- Last error state.

Never force a fresh navigation if `WKWebView.interactionState` restore succeeds.

### 6.4 Recovery states

User-facing recovery text should be compact:

- Restored normally.
- Restored from previous snapshot.
- Restored with missing terminal process.
- Dropped invalid browser state.
- State file was unreadable; started a clean workspace.

Diagnostics should include exact file paths and error details. User UI should not show raw
JSON unless the user opens diagnostics.

## 7. Attention System

### 7.1 Event model

```swift
struct ConductorAttentionEvent: Codable, Identifiable, Equatable {
    var id: UUID
    var createdAt: Date
    var kind: Kind
    var severity: Severity
    var title: String
    var body: String
    var workspaceID: WorkspaceID?
    var terminalID: TerminalID?
    var webTabID: WebTabID?
    var source: String
    var readAt: Date?
    var details: [String: String]
}
```

Kinds:

- agentReply
- terminalBell
- commandFinished
- updateAvailable
- updateFailed
- browserError
- sessionRecovery
- permissionWarning

### 7.2 Delivery paths

Every event enters the in-app store. Some events also try macOS Notification Center.

```text
hook / app event
      │
      ▼
ConductorNotificationCenter
      ├── persist event
      ├── update workspace unread state
      ├── render toast if appropriate
      └── deliver macOS notification if allowed
```

If macOS delivery fails, the event still exists in-app. Permission state is visible in
settings and diagnostics.

### 7.3 Unread behavior

- Workspace unread count increments when an event points to that workspace.
- Terminal unread badge appears only when event targets that terminal.
- Opening/focusing the target should mark events read only when the user explicitly lands
on the target, not just when the app becomes active.
- "Clear all" asks for confirmation only if many unread events exist.

### 7.4 Settings behavior

Settings should say:

- Notifications are allowed.
- Notifications are denied by macOS.
- Notifications have not been requested.
- Notifications unavailable because Conductor was launched outside `.app`.

The test button should create both an in-app event and attempt a macOS banner, then report
both results.

**2026-06-03 implementation status:** `ConductorAttentionEvent` and
`ConductorAttentionStore` now live in `ConductorCore`. The app model can create, list,
focus, and clear events; agent reply notifications create in-app events before attempting
macOS delivery; the control protocol exposes notification create/list/focus/clear; and
`app.status`/`app.diagnostics` expose unread counts and store metadata. UI badges,
notification panel rendering, permission-state settings, duplicate suppression, terminal
desktop-notification escape ingestion, agent-reply banner click-through to stored events,
terminal-attention banner attempts, command-finished events for failed or long-running
unattended commands, and banner-failure in-app toast are live. The remaining gap is
permission-state automation across every macOS authorization state.

## 8. Browser Surface Design

### 8.1 Browser modes

The browser surface has two modes:

- Human browsing: address/search, back/forward, reload/stop, open external, find.
- Protocol automation: snapshot, screenshot, click, fill, press, wait, find, evaluate.

These modes share one WebKit instance per tab. Automation should never create hidden
browser state that the user cannot see.

### 8.2 Snapshot model

`browser.snapshot` returns a bounded object:

```json
{
  "url": "https://example.com",
  "title": "Example",
  "text": "bounded visible/main text",
  "links": [
    { "ref": "link-1", "text": "Docs", "href": "https://example.com/docs" }
  ],
  "fields": [
    { "ref": "input-1", "type": "text", "label": "Search", "value": "" }
  ],
  "buttons": [
    { "ref": "button-1", "text": "Submit" }
  ],
  "selection": ""
}
```

Automation commands accept stable refs from the latest snapshot (`link-0`, `button-0`,
`field-0`) plus CSS selectors as a fallback for advanced users.

`browser.screenshot` returns a visible-viewport PNG export:

```json
{
  "webTabID": "...",
  "url": "https://example.com",
  "title": "Example",
  "path": "/var/folders/.../Conductor/BrowserScreenshots/browser-....png",
  "width": 1512,
  "height": 982,
  "scale": 2
}
```

It captures the WebKit surface the user can see, not a hidden automation-only browser.

`browser.click`, `browser.fill`, and `browser.press` return a bounded action result:

```json
{
  "webTabID": "...",
  "action": "click",
  "target": "button-0",
  "matched": true,
  "message": "Clicked Submit.",
  "text": "Submit",
  "value": "",
  "url": "https://example.com"
}
```

`browser.wait` uses the same envelope for load, selector, visible element, and text
conditions. Load waits for `document.readyState == complete`; selector/visible waits
accept snapshot refs or CSS selectors; text waits for visible body text and populates
`matches` when it succeeds. `browser.find` returns the same envelope with `matches`
populated. `browser.evaluate`
returns the same envelope with `result` and `resultType` populated, truncating large
results instead of streaming arbitrary page state.

### 8.3 Errors and safety

- Common selector, text, script, unsupported Promise, and timeout failures return
  typed `automationError` details so scripts can branch without parsing prose.
- Page script failures return bounded stack/message.
- Screenshots write to a temporary file and return the path.
- JS evaluation is synchronous and trusted. Promise-returning scripts fail with
  `promise_unsupported` until the async bridge is explicitly designed.
- No password or cookie data should be exposed in snapshots.
- Advanced wait states, dialog/download handling, frame-specific targeting,
  cross-origin behavior, stress coverage, and user-facing error UI are still
  required for cmux-level browser reliability.

## 9. Workspace Intelligence

### 9.1 Metadata model

```swift
struct WorkspaceMetadataSnapshot: Equatable {
    var workspaceID: WorkspaceID
    var rootURL: URL?
    var projectName: String
    var runningPorts: [RunningPort]
    var activeAgents: [AgentSummary]
    var unreadCount: Int
    var lastActivityAt: Date?
}
```

### 9.2 Local Services

Local service readers should be:

- Debounced.
- Scoped to visible/recent workspaces.
- Cancelable.
- Timeout-bounded.
- Non-blocking on main thread.

Show:

- Running local services.
- Port state.
- Health when scanning is partial.

### 9.3 Ports

Port detection should be best effort. It should not require elevated permissions.

Show:

- Port number.
- Process name when available.
- Quick open if URL can be inferred.

### 9.4 Agent state

Agent state comes from terminal metadata and hook events:

- idle
- running
- waiting for input
- replied/unread
- errored

Avoid provider-specific branding in main product chrome unless it helps identify the
running tool.

## 10. Command and Shortcut Layer

### 10.1 Command record

Every command should have:

- ID.
- Localized title.
- Plain outcome description.
- Category.
- Enabled predicate.
- Default shortcut.
- User shortcut.
- Context tags.
- Protocol method when applicable.

### 10.2 Command palette behavior

- Search title, description, category, and keywords.
- Rank enabled/contextual/recent commands first.
- Show shortcut badges.
- Show disabled commands only when search matches exactly enough, with reason.
- Enter runs command; Escape closes; arrows navigate.

### 10.3 Shortcut safety

- Settings, command palette, notification panel, update panel, and modal overlays must
  prevent unrelated global app shortcuts.
- Only close/toggle shortcuts should pierce panels.
- Recorder must reject reserved system shortcuts and show conflict with existing app
  commands.

## 11. Native UX Tokens

### 11.1 Token families

| Token family | Examples |
| --- | --- |
| Radius | window, panel, card, control, small control |
| Space | sidebar width, toolbar gap, row padding, panel padding |
| Typography | sidebar title, row primary, row secondary, metadata, button |
| Color | background, chrome, surface, selected, hover, separator, text |
| Motion | hover, press, panel open, list insert, drag, reduced motion |
| Elevation | panel shadow, popover shadow, selected row emphasis |

### 11.2 Themes

Themes must be token sets, not scattered one-off color overrides. Required family spread:

- Clean light.
- Clean dark.
- Warm light.
- Graphite.
- Glass light.
- Glass dark.
- Low contrast.
- High contrast.
- Gradient subtle light.
- Gradient subtle dark.

Every theme must pass:

- Toolbar readability.
- Terminal readability.
- Settings readability.
- Notification panel readability.
- Disabled/hover/selected states.

### 11.3 Motion

Motion should communicate causality, not personality.

- Hover: 100-140 ms.
- Press: instant to 90 ms.
- Panel open: 140-180 ms.
- List insert/remove: 120-180 ms.
- Drag transitions: stable and not springy.
- Respect reduced motion globally.

## 12. Update UX

### 12.1 States

```text
idle
checking
upToDate
available(version, notes)
downloading(progress)
downloaded
installing
failed(reason)
```

### 12.2 User-facing copy

Good:

- "Update available"
- "Downloading 0.0.2"
- "Ready to install"
- "Download failed. Try again."

Bad:

- Raw manifest URL.
- "Asset not available" without context.
- Internal architecture labels unless in diagnostics.

### 12.3 Toolbar pill

Only appears when:

- update available
- downloading
- ready to install
- failed and retry is useful

It should not occupy chrome when app is up to date.

## 13. Observability

### 13.1 Diagnostics bundle

Bundle includes:

- App version/build/arch.
- Launch context: `.app` or `swift run`.
- Notification authorization state.
- Last 50 attention events metadata.
- Update state and last error.
- Session restore summary.
- Workspace counts.
- Surface counts.
- Main-thread stall events.
- Recent protocol errors.

### 13.2 Performance budgets

Initial targets:

- Settings open below 250 ms after warm launch.
- Command palette open below 120 ms.
- Workspace switch below 150 ms for ordinary workspaces.
- Terminal tab switch should feel immediate; no accidental drag on click.
- 10 idle terminals should not scale steady-state CPU linearly.
- Browser tab restore should not freeze the main thread.

These are working targets, not marketing claims. Diagnostics should record enough to
evaluate them locally.

## 14. Release and Docs

### 14.1 Release artifacts

For each release:

- arm64 zip.
- x86_64 zip.
- latest manifest per arch.
- checksums.
- release notes.
- screenshots from current build.

### 14.2 README content

README should answer:

- What is Conductor?
- Who is it for?
- What can it do today?
- How do I install?
- Why does macOS ask security questions?
- How do updates work?
- How do notifications work?
- How do I script it?
- How do I report issues?

### 14.3 Honest limitations

If no Developer ID:

- Say builds are ad-hoc signed.
- Explain first-launch Gatekeeper behavior.
- Do not pretend it is a notarized commercial build.

## 15. Acceptance Scenarios

### 15.1 Protocol dogfood

Run one script that:

- Creates a workspace.
- Splits two terminals.
- Sends commands.
- Opens a web tab.
- Creates a notification.
- Queries state.
- Takes a browser screenshot.

All actions are visible in UI.

### 15.2 Notification permission matrix

Test:

- authorized
- denied
- not determined
- launched via `swift run`
- launched as `.app`

Each case produces correct settings state, diagnostics, and in-app event behavior.

### 15.3 Crash restore

Create a workspace with:

- 3 panes.
- 4 terminal tabs.
- 2 web tabs.
- 1 file tab.
- 3 unread notifications.

Force quit and relaunch. Verify state restores or explains every missing piece.

### 15.4 UI containment

Open settings. Press every common app shortcut. Verify only allowed close/toggle behavior
affects the panel; hidden terminals and tabs do not change.

### 15.5 Update

Simulate:

- no update
- update available
- download progress
- checksum failure
- ready to install

Normal UI never shows raw URLs. Diagnostics includes raw technical details.

## 16. Implementation Rule

Each implementation PR or commit should state which design section it advances. If a
feature cannot satisfy the relevant acceptance scenario yet, it must add a diagnostic or
test hook that makes the remaining gap measurable.
