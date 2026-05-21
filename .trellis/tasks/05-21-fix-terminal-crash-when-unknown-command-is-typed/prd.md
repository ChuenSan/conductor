# Fix terminal crash when unknown command is typed

## Problem
Conductor crashes after the user types an unknown command such as `sls` in a terminal. Unknown shell commands must be treated as normal terminal output and must never crash the app.

## Acceptance Criteria
- Typing `sls` or another unknown command in an active terminal does not crash Conductor.
- The terminal remains interactive after the shell prints its command-not-found output.
- Crash root cause is fixed at the terminal/notification/parsing boundary, not hidden by disabling terminal input.
- Existing terminal performance rule remains intact: terminal output/scrollback does not enter SwiftUI state.
- Verification includes the project check script and, if possible, launching the app after the fix.
