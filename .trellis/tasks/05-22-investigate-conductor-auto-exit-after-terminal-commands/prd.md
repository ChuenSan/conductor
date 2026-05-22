# Investigate Conductor Auto Exit After Terminal Commands

## Goal

Find why the freshly built Conductor app appears to quit automatically after several terminal commands, especially around user input, without an obvious crash dialog or local app log.

## What I Already Know

* The app was freshly built from `main` at `/Users/cses-38/workspace/conductor/Apps/Conductor/.build/Conductor.app`.
* The user observed the app disappearing after typing several commands; one prior repro involved typing `sls`.
* The user clarified the repro was several commands plus Return typed quickly.
* The symptom feels like an automatic exit, not a normal crash report.
* Terminal behavior is GhosttyKit/libghostty-backed; project rules forbid pushing terminal scrollback or high-frequency terminal output into SwiftUI state.

## Assumptions

* The failure may be one of: normal process exit, explicit app termination, uncaught native fatal error, AppKit window lifecycle quit, PTY/session teardown causing app shutdown, or process kill by the OS.
* Because there is no obvious crash log, macOS unified logs and recent diagnostic reports need to be checked before changing code.

## Requirements

* Confirm whether Conductor is exiting normally, crashing, aborting, or being killed.
* Reproduce with the current release app if possible.
* Inspect terminal input/session lifecycle code for cases where command errors or PTY EOF can close the app.
* Pay special attention to fast keyboard input, Return handling, IME/cursor positioning, and Ghostty close callbacks.
* If root cause is found and low-risk, fix it in the smallest scoped change.
* Preserve terminal rendering architecture and avoid routing high-frequency terminal output through SwiftUI state.

## Acceptance Criteria

* [ ] Recent macOS diagnostic reports and unified logs are inspected for Conductor around the observed time.
* [ ] The app is run from Terminal once so stdout/stderr exit behavior can be captured.
* [ ] Candidate terminal input/session/window-lifecycle paths are inspected.
* [ ] If a code fix is made, the app builds and can be launched again.
* [ ] The result explains whether the evidence points to pointer/native crash, app lifecycle exit, or another cause.

## Out of Scope

* Broad redesign of terminal rendering.
* File manager or document viewer performance work unless it directly triggers the exit.
* Committing or pushing without explicit user request.

## Technical Notes

* Relevant specs to read before code changes: high-performance terminal roadmap, frontend component guidelines, frontend state management, backend quality guidelines, GhosttyKit integration.
