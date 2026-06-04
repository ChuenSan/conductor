# Getting Started

Conductor is a native macOS workbench for terminal-heavy development. It keeps terminal panes, web references, files, notifications, usage records, settings, and updates close together without turning the whole app into a dashboard.

## Requirements

- macOS 14 or newer.
- For source builds: Xcode Command Line Tools and a Swift 6 toolchain.
- For release builds: a downloaded `Conductor.app` from GitHub Releases.

## Install From A Release

1. Download the latest macOS release from GitHub Releases.
2. Unzip the archive.
3. Move `Conductor.app` into `/Applications`.
4. Launch the app.

Public preview builds may be ad-hoc signed. If macOS blocks the first launch, right-click the app, choose **Open**, then confirm. See [Troubleshooting](troubleshooting.md) for Gatekeeper details.

## Build From Source

```bash
git clone https://github.com/zhengzizhe/conductor.git
cd conductor/Apps/Conductor
./Scripts/prepare-ghosttykit.sh
swift build
swift run ConductorModelCheck
./Scripts/run-conductor.sh
```

Build a clickable app bundle:

```bash
cd Apps/Conductor
./Scripts/build-app-bundle.sh
open .build/Conductor.app
```

## Verify The Local Control API

The app exposes a user-local control socket so scripts can create workspaces, split panes, send terminal text, open web tabs, run commands, and create attention events.

Build the CLI:

```bash
cd Apps/Conductor
swift build --product ConductorCLI
```

With Conductor running:

```bash
.build/debug/ConductorCLI ping
.build/debug/ConductorCLI status
.build/debug/ConductorCLI workspace create --title "Release"
.build/debug/ConductorCLI terminal send --text "pwd\n"
```

Run the smoke script:

```bash
./Scripts/control-smoke.sh
```

For isolated test runs, use a temporary socket and state path:

```bash
CONDUCTOR_STATE_PATH=/tmp/conductor-state/window-state.yaml \
CONDUCTOR_CONTROL_SOCKET_PATH=/tmp/conductor-state/control.sock \
.build/debug/Conductor
```

Then run:

```bash
CONDUCTOR_CONTROL_SOCKET_PATH=/tmp/conductor-state/control.sock \
CONDUCTOR_SMOKE_SKIP_CLI_BUILD=1 \
./Scripts/control-smoke.sh
```

## Local State

Conductor stores user state in:

```text
~/Library/Application Support/Conductor/
```

Important files:

- `window-state.yaml`: workspace layout, selected workspace/content, appearance, web tabs, and file tabs.
- `window-state.json`: legacy state file read for compatibility.
- `attention-events.json`: in-app notification and attention event store.
- `control.sock`: local control socket while the app is running.

Useful development flags:

```bash
CONDUCTOR_RESET_STATE=1 ./Scripts/run-conductor.sh
CONDUCTOR_DISABLE_PERSISTENCE=1 ./Scripts/run-conductor.sh
CONDUCTOR_STATE_PATH=/tmp/window-state.yaml ./Scripts/run-conductor.sh
```

## First Things To Try

- Create a workspace.
- Split a terminal right or down.
- Open a web tab for project docs.
- Start a local dev server in a terminal, then open the workspace inspector to jump back to its localhost URL.
- Open the command palette and run a workspace command.
- Open settings and choose a theme.
- Trigger a test notification or create one through the CLI.

## Next Docs

- [Local control API](api.md)
- [Notifications](notifications.md)
- [Updating Conductor](updating.md)
- [Troubleshooting](troubleshooting.md)
