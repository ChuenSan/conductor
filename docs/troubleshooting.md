# Troubleshooting

This page collects common Conductor problems and what to check first.

## App Will Not Open

### macOS Says The App Cannot Be Verified

Public preview builds may be ad-hoc signed.

Try:

1. Move `Conductor.app` to `/Applications`.
2. Right-click `Conductor.app`.
3. Choose **Open**.
4. Confirm the prompt.

If the release says it is Developer ID signed and notarized but macOS still blocks it, report the release version and macOS version.

### App Opens To A Blank Or Unexpected Workspace

Try launching with a clean state:

```bash
cd Apps/Conductor
CONDUCTOR_RESET_STATE=1 ./Scripts/run-conductor.sh
```

For release builds, the state directory is:

```text
~/Library/Application Support/Conductor/
```

Do not delete state files until you have copied anything you may need for debugging.

## Notifications

### Sound Plays But No Banner Appears

Possible causes:

- macOS notifications are denied for Conductor.
- Focus mode is suppressing banners.
- The app was launched as a debug binary rather than a normal `.app`.
- Notification Center delayed or dropped the banner.

In-app attention events may still exist. Check with:

```bash
cd Apps/Conductor
.build/debug/ConductorCLI notify list
```

### Notification Focus Fails

The target workspace, terminal, or web tab may have been closed. The local API should return a `target_not_found` error.

### Test Notification Does Not Request Permission

macOS notification permission is most reliable when Conductor is launched as `Conductor.app`. Debug binary launches can be marked unavailable by diagnostics.

## Updates

### Update Button Does Not Appear

Possible causes:

- the app is already up to date
- no compatible release asset exists for the current architecture
- GitHub is unreachable
- the update channel is not configured
- the update check failed silently and needs diagnostics

Check the update section in settings and run diagnostics if available.

### Download Is Slow Or Has No Progress

Possible causes:

- GitHub asset download is slow
- network is throttled
- the server did not provide reliable content length
- the progress UI is still waiting for download callbacks

Retry once before filing a bug. Include app version, release version, and network context if you report it.

### Install Fails

Possible causes:

- checksum mismatch
- wrong bundle identifier
- code signing verification failed
- app is in a read-only location
- external installer could not replace the app

Move `Conductor.app` to `/Applications` and retry.

## Local Control API

### CLI Says App Is Not Running

The socket may not exist or may be stale:

```text
~/Library/Application Support/Conductor/control.sock
```

Check:

```bash
cd Apps/Conductor
.build/debug/ConductorCLI ping
```

If you launched the app with a custom socket:

```bash
CONDUCTOR_CONTROL_SOCKET_PATH=/tmp/conductor-control.sock \
.build/debug/ConductorCLI ping
```

### Smoke Script Hangs While Building CLI

SwiftPM can spend time reevaluating dependency manifests. If the CLI is already built, run:

```bash
CONDUCTOR_SMOKE_SKIP_CLI_BUILD=1 ./Scripts/control-smoke.sh
```

## Performance

### Terminal Scroll Feels Blocky

Useful details for a bug report:

- macOS version
- machine model and architecture
- theme
- number of panes
- whether output is still streaming
- whether the app is in a large window or external display

### Settings Or Usage Panel Opens Slowly

Include:

- app version
- whether it happens on first open only or every open
- number of configured usage providers
- screenshot or screen recording if possible

## Diagnostics Checklist

When reporting a bug, include:

- Conductor version and build
- macOS version
- whether it is a release app or source/debug launch
- steps to reproduce
- whether persistence was enabled
- relevant CLI output from `ConductorCLI diagnostics`
- a redacted diagnostics bundle from `ConductorCLI diagnostics export --output ~/Desktop`

Diagnostics export redacts common home paths and email-like values. Before sharing
the bundle, still review it for project names, command text, and any private
workspace details that may appear in diagnostic events.
