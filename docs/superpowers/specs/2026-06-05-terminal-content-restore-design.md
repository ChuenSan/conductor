# Terminal Content Restore Design

## Status

Drafted on 2026-06-05. Scope is limited to restoring terminal content as a
read-only text snapshot and showing agent resume hints inside that restored
content. The design does not restore shell processes, PTYs, VT state, or live
terminal scrollback.

## Context

Conductor now restores compact workspace/window state across launches. Terminal
tabs, panes, workspace layout, working directories, and `TerminalAgentSnapshot`
metadata can survive in the workspace model, but terminal display content does
not. After relaunch, every terminal starts a fresh shell, so the user loses the
visible context from the previous app session.

Current code provides useful building blocks:

- `TerminalSurface.visibleText()` can read the current visible viewport text.
- `TerminalAgentSnapshot` stores agent provider, display name, lifecycle state,
  session identifier, and resume command.
- `AgentResumeDetector` can build supported resume commands for Codex and
  Claude Code:
  - `codex resume <session-id>`
  - `claude --resume <session-id>`
- Workspace restore already recreates terminal tabs and their metadata.

## Goals

1. Save a compact text snapshot for each visible/restorable terminal.
2. Restore that snapshot after launch as read-only historical content.
3. Append a Codex/Claude resume hint as the final restored-content line when a
   terminal has supported agent resume metadata.
4. Keep restored content separate from the new live shell input/output stream.
5. Avoid automatic resume execution and avoid injecting text into the live
   terminal.
6. Keep snapshots bounded in size and safe to persist.
7. Make the feature testable with isolated state paths and control socket runs.

## Non-Goals

- Restoring shell processes.
- Restoring PTY state.
- Restoring VT bytes or exact terminal screen attributes.
- Replaying keystrokes.
- Writing resume commands into the live terminal input buffer.
- Automatically executing `codex resume` or `claude --resume`.
- Reintroducing unbounded session journals.

## Product Behavior

On normal app quit or persistence flush, Conductor captures the latest visible
text for each terminal that has a live surface. The snapshot is saved beside the
workspace state in a bounded terminal-content snapshot file.

On launch, after workspace state is restored, Conductor loads matching terminal
content snapshots by terminal id. The restored content is shown as read-only
historical text for that terminal. The live terminal still starts a new shell.

If the terminal has a supported `TerminalAgentSnapshot`, Conductor appends one
final line to the restored text:

```text
Conductor restore hint: codex resume <session-id>
```

or:

```text
Conductor restore hint: claude --resume <session-id>
```

This line is visual context only. It is not sent to the terminal, not copied
automatically, and not executed automatically.

## Data Model

Add a bounded persisted model separate from `window-state.yaml`:

```swift
struct PersistedTerminalContentSnapshot: Codable, Equatable {
    var terminalID: TerminalID
    var workspaceID: WorkspaceID
    var paneID: PaneID?
    var capturedAt: Date
    var workingDirectory: String?
    var text: String
    var agentSnapshot: TerminalAgentSnapshot?
}

struct PersistedTerminalContentSnapshotFile: Codable, Equatable {
    var schemaVersion: Int
    var capturedAt: Date
    var snapshots: [PersistedTerminalContentSnapshot]
}
```

Suggested file:

```text
~/Library/Application Support/Conductor/terminal-content-snapshots.yaml
```

When `CONDUCTOR_STATE_PATH` is set, derive the terminal snapshot path from the
override state file, for example:

```text
<state-file-directory>/terminal-content-snapshots.yaml
```

## Snapshot Rules

- Capture only visible viewport text available from `TerminalSurface.visibleText()`.
- Trim trailing whitespace-only lines.
- Cap each terminal snapshot to 32 KiB of UTF-8 text.
- Cap total snapshots to currently known terminal ids.
- Drop snapshots for terminal ids that no longer exist in restored workspace
  state.
- Persist `agentSnapshot` from the terminal tab when available.
- If visible text is empty but an agent resume hint exists, keep a snapshot whose
  only restored line is the hint.
- Never persist ANSI/VT control bytes intentionally. If visible text contains
  control characters, normalize to printable newlines/tabs plus Unicode text.

## Restore Rules

On `ConductorWindowModel.init()`:

1. Load workspace state.
2. Load terminal content snapshots.
3. Filter snapshots to restored terminal ids.
4. For every matching terminal, attach a read-only restored-content preview.
5. Build the final displayed restored text by appending one resume hint line
   when `AgentResumeDetector.metadata(providerID:sessionIdentifier:)` can create
   a command from the terminal's agent metadata.

When both the workspace terminal tab and terminal content snapshot contain agent
metadata, prefer the workspace tab's `TerminalAgentSnapshot`, then fall back to
the snapshot's `agentSnapshot`.

## UI Model

Add runtime state keyed by `TerminalID`:

```swift
struct RestoredTerminalContent: Equatable {
    var terminalID: TerminalID
    var capturedAt: Date
    var text: String
    var resumeHint: String?
}
```

The terminal pane should render a read-only restored content block when one is
available. The block should be visually distinct from the live shell. It can be
dismissed per terminal without deleting the persisted snapshot immediately.

The initial implementation does not need a full recovery toolbar. A compact
read-only block with timestamp and text is enough, as long as the final line
shows the restore hint when available.

## Agent Resume Semantics

Codex and Claude resume hints are display-only:

- They appear only as the final line of restored content.
- They are never sent through `controlSendText`.
- Existing `terminal.resumeAgent` and `terminal.resumeAgents` control protocol
  actions can continue to send resume commands explicitly when the user or CLI
  calls them.
- The restored-content feature does not change those explicit resume actions.

## Persistence Lifecycle

Terminal content snapshot saving should happen in the same moments as compact
workspace persistence:

- `flushPersistence()`
- debounced persistence after workspace/terminal metadata changes
- app quit through control protocol or normal app lifecycle

Writing snapshots should be background-friendly and bounded. Failures should not
block workspace persistence.

`CONDUCTOR_DISABLE_PERSISTENCE=1` disables terminal content snapshot saving and
loading.

`CONDUCTOR_RESET_STATE=1` removes terminal content snapshots together with window
state.

## Testing Strategy

Unit tests:

- `AgentResumeDetector` still emits safe Codex and Claude commands.
- restored-content formatting appends the hint as the final line.
- formatting does not append duplicate hints.
- snapshot sanitization trims and caps text.
- snapshot loading drops terminal ids that are not in the restored workspace.

Model or integration checks:

- With isolated `CONDUCTOR_STATE_PATH` and `CONDUCTOR_CONTROL_SOCKET_PATH`,
  create a workspace with multiple terminals, simulate or capture visible text,
  quit, relaunch, and assert restored content exists for the same terminal ids.
- Assert the restored content for a Codex terminal ends with
  `Conductor restore hint: codex resume <session-id>`.
- Assert the restored content for a Claude terminal ends with
  `Conductor restore hint: claude --resume <session-id>`.
- Assert no `session-journal.ndjson` or `session-snapshots/` directory is
  created.

Validation commands:

```bash
cd Apps/Conductor
swift test
swift build --disable-build-manifest-caching --product Conductor
swift run ConductorModelCheck
```

## Risks

- Users may confuse restored text with live shell output. The UI must clearly
  mark it as restored historical content.
- `visibleText()` captures only the viewport, not full scrollback. This is
  intentional for performance and predictability.
- Resume hints can become stale if an external CLI invalidates or deletes the
  session. The hint is still useful as the best known recovery command.
- Captured terminal text may contain sensitive data. Keep the feature bounded,
  local-only, and controlled by the existing persistence disable/reset knobs.

## Success Criteria

- Relaunch restores visible terminal context as read-only text.
- Restored content is separate from the new shell stream.
- Codex and Claude resume commands are visible only as the final restored line.
- No resume command is injected or executed automatically.
- Snapshot files stay bounded and are removed by reset.
- Existing workspace restore continues to pass.
