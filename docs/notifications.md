# Notifications And Attention

Conductor treats a notification as a navigable event, not just a sound. The goal is simple: when a background terminal task or agent reply needs attention, the user should know what happened and where to go.

## Notification Layers

Conductor has two notification layers:

1. **In-app attention events:** stored locally in `attention-events.json`.
2. **macOS Notification Center banners:** shown only when macOS allows them.

The in-app layer is the source of truth. macOS banners are helpful, but they can be denied, unavailable, or delayed by the system.

## What Is Stored

An attention event stores:

- event ID
- timestamp
- kind and severity
- title and body
- workspace ID when known
- terminal ID when known
- web tab ID when known
- source
- read/unread state
- extra details for diagnostics

This lets Conductor focus the right workspace or surface from a notification ID.

## Current Behavior

Implemented:

- Agent reply hooks create in-app attention events.
- Control API notifications create in-app attention events.
- `notification.list`, `notification.focus`, and `notification.clear` work through the local API.
- `app.status` and `app.diagnostics` report unread attention counts and store metadata.
- Notifications are delivered through native macOS banners and sounds when macOS allows them.
- The command palette exposes jump-to-latest-unread and mark-current-workspace-read actions. Jumping prefers the current workspace's unread events, then falls back to the newest unread event globally.
- CLI notifications can include `--workspace`, `--terminal`, or `--web-tab` so scripts can create events that focus an exact surface.
- Workspace rows, collapsed sidebar workspace icons, and top workspace tabs show compact unread indicators with hover text.
- A shell toast explains when a macOS banner cannot be shown because notification permission is unavailable or delivery fails.
- Settings show the macOS notification permission state as allowed, denied, not requested, unavailable, or unknown.
- Settings and the CLI can send a real test system notification and report whether Notification Center accepted it.
- Rapid duplicate agent-reply notifications from the same terminal/source are folded into one unread event, with diagnostics for the suppressed count.
- Ghostty desktop-notification actions from terminal escape sequences create in-app terminal alert events with the originating terminal target and attempt a macOS banner when notifications are available.
- Conductor enables Ghostty command-finish reporting and filters it in the app layer. Background non-agent terminal commands create command-finished attention events when they fail or run for at least 30 seconds before finishing. The event keeps the originating terminal target, exit code, duration, and reason.
- Non-agent command-finished events also attempt a macOS banner. Clicking that banner focuses the stored attention event and selects the originating terminal.
- Clicking an agent-reply macOS banner focuses the stored in-app event, selects the target terminal when available, and marks that event read. Older banners without an event ID fall back to the newest unread event for the terminal, then the terminal itself.
- Session restore fallback or failure creates an in-app recovery event.

Still in progress:

- End-to-end `.app` automation for every macOS permission state. The pure delivery policy is unit-tested for allowed, denied, not-requested, unavailable, unknown, delivery success, and delivery failure states.

## macOS Permission States

Conductor can be in one of these states:

- **Allowed:** macOS banners can be delivered.
- **Denied:** in-app events still work, but macOS banners will not show.
- **Not requested:** the app has not asked macOS yet.
- **Unavailable outside app bundle:** debug launches may not behave like a normal `.app` bundle.

If sound plays but no banner appears, check macOS notification settings first. In-app events may still exist even when Notification Center does not show a banner.

## Test With The CLI

With Conductor running:

```bash
cd Apps/Conductor
swift build --product ConductorCLI

.build/debug/ConductorCLI notify "Build finished" --body "npm test passed"
.build/debug/ConductorCLI notify "Agent finished" --workspace <workspace-id> --terminal <terminal-id>
.build/debug/ConductorCLI notify test --title "Conductor test" --body "Checking Notification Center"
.build/debug/ConductorCLI notify list
```

`notify test` returns `status`, `authorization`, `launchSupportsSystemNotifications`, and `addedToNotificationCenter`. If the app was started from a debug binary, `launchSupportsSystemNotifications` is usually `false`; the in-app notification layer still works.

Focus and clear a specific event:

```bash
.build/debug/ConductorCLI notify focus <notification-id>
.build/debug/ConductorCLI notify clear <notification-id>
```

Jump to the newest unread event, or mark a workspace as read:

```bash
.build/debug/ConductorCLI notify latest
.build/debug/ConductorCLI notify mark-read --workspace <workspace-id>
```

`notify latest` and the command-palette "Jump to Latest Unread" action first
try the current workspace's unread events. If that workspace is quiet, they jump
to the newest unread event anywhere in the workbench.

Clear all attention events:

```bash
.build/debug/ConductorCLI notify clear
```

## Diagnostics

```bash
.build/debug/ConductorCLI diagnostics
```

Diagnostics include:

- attention store path
- event count
- unread count
- latest session journal information
- control socket path
- notification authorization and current launch support for macOS banners

## Troubleshooting

### Sound Plays But No Banner Appears

Likely causes:

- macOS notifications are denied for Conductor.
- The app was launched from a debug binary instead of a normal `.app`.
- Notification Center is suppressing alerts due to Focus mode or system settings.

The in-app attention event should still be present through the local API.
Run `notify test` or use Settings -> 自动化/通知 -> 系统通知 -> 测试 to see whether the notification was accepted by Notification Center.

### Notification Exists But Focus Fails

The target workspace, terminal, or web tab may have been closed. The API returns `target_not_found` when a notification can no longer focus its original target.

### Too Many Repeated Notifications

Agent-reply bursts from the same terminal/source are folded into the existing unread event for a short window. The notification row shows how many duplicates were merged, and diagnostics record the suppressed count. If repeated notifications still appear as separate rows, check whether they came from different terminals, sources, or a time window outside the debounce period.

### Terminal Escape Notification Does Not Show A Banner

Terminal desktop-notification escapes are always recorded as in-app terminal alerts. If a system banner does not appear, check `diagnostics.notifications.launchSupportsSystemNotifications`, the authorization state, and the diagnostics log for `terminal-attention-notification-skipped` or `terminal-attention-notification-failed`.
