# Workspace Restore Design

## Status

Drafted on 2026-06-05 for implementation. Scope is intentionally limited to
workspace/window state restoration. Terminal content restoration remains deleted
and out of scope.

## Context

Conductor currently writes compact workspace state to:

```text
~/Library/Application Support/Conductor/window-state.yaml
```

The persisted payload includes workspaces, selected workspace, terminal pane and
tab metadata, appearance, web tabs, file tabs, and selected workspace content.
However, the app startup path currently initializes `ConductorWindowModel` with a
fresh `WorkspaceState()` and does not read the persisted state back.

This creates a confusing product behavior: the app appears to persist state on
disk, but packaged launches do not restore the user's workspace topology.

Historical terminal content restore work existed, but was intentionally removed
by `3b5ab86b refactor: remove session content restore`. This design does not
bring that system back.

## Goals

1. Restore compact workspace state on normal app launch.
2. Preserve the current persisted file format and tolerate legacy JSON.
3. Restore all workspace topology:
   - workspace list
   - selected workspace
   - split tree
   - panes
   - terminal tabs
   - focused pane
   - selected terminal/file/web content tab
4. Restore lightweight non-terminal content:
   - web tab metadata
   - file tab metadata
   - selected file/web tab
5. Restore lightweight preferences:
   - theme
   - appearance
   - keyboard shortcuts in `AppearancePreferences`
6. Avoid overwriting a valid saved state with the default workspace during startup.

## Non-Goals

- Restoring terminal output text.
- Restoring scrollback.
- Restoring VT bytes.
- Recreating shell processes.
- Reintroducing `session-journal.ndjson`.
- Reintroducing `session-snapshots/`.
- Reintroducing session recovery settings UI.
- Reintroducing terminal content preview or replay.

## Product Behavior

On launch, Conductor should:

1. Read `window-state.yaml` if persistence is enabled.
2. Fall back to legacy `window-state.json` if YAML is missing or invalid.
3. Start with the restored selected workspace if valid.
4. Rebuild Ghostty terminal surfaces for restored terminal tabs.
5. Use restored terminal working directories for new shell sessions.
6. Restore file/web tabs as metadata-only surfaces.
7. If no valid state exists, create a default workspace exactly as today.

`CONDUCTOR_RESET_STATE=1` deletes persisted window state and starts clean.

Validation and automation launches that set `CONDUCTOR_DISABLE_PERSISTENCE=1` or
autorun flags keep their current isolated behavior.

## Data Model

Use the existing model:

```text
PersistedWindowState
  workspaces
  selectedWorkspaceID
  theme
  appearance
  workspaceWebTabs
  workspaceFileTabs
  selectedWorkspaceContentTabID
  workspaceContentStates
```

`WorkspacePersistence.load()` should return a sanitized
`PersistedWindowState?`, not raw decoded data.

Sanitization rules:

- Reconcile every workspace split tree with its panes.
- Drop invalid workspaces.
- Choose the first valid workspace if `selectedWorkspaceID` is missing or invalid.
- Clear web runtime flags: loading, progress, back/forward, transient errors.
- Drop missing file tabs and de-duplicate by file path.
- Validate selected content against the restored workspace/file/web sets.
- Preserve terminal selected tab IDs and focused pane IDs when valid.

## Startup Flow

`ConductorWindowModel.init()` should:

1. Call `persistence.load()`.
2. If a valid state exists:
   - initialize `workspaces`
   - initialize `selectedWorkspaceID`
   - initialize `workspace`
   - initialize `theme`
   - initialize `appearance`
   - initialize per-workspace content runtime state
   - apply the selected workspace's content state
3. Otherwise use the current default initialization path.
4. Only then wire coordinators, runtime appearance, notifications, polling, and
   metadata refresh.

The initializer must not call `persist()` before applying restored state.

## Compatibility

The loader must tolerate:

- YAML state files written by current builds.
- Legacy JSON files.
- Legacy payloads with a single `workspace` field.
- Missing newer fields.
- Workspaces with stale or incoherent split tree data.

## Test Strategy

Add focused model checks or Swift tests for:

- YAML round-trip restores multiple workspaces.
- Legacy JSON state still loads.
- Invalid selected workspace falls back to the first valid workspace.
- Invalid workspace topology is reconciled or dropped.
- Missing file tabs are removed.
- Web runtime flags are cleared.
- Startup model uses restored selected workspace rather than default workspace.
- `CONDUCTOR_RESET_STATE=1` starts clean.

Manual validation:

1. Launch packaged app.
2. Create two workspaces.
3. Add split panes and extra terminal tabs.
4. Open a file tab and a web tab.
5. Quit.
6. Reopen packaged app.
7. Confirm the same workspace topology and content tab selection returns.
8. Confirm no `session-journal.ndjson` or `session-snapshots/` is created.

## Risks

- Startup can overwrite saved state if default state is persisted before loading.
- Invalid stale state can crash if selection is not validated.
- Existing debug/autorun workflows can accidentally read real user state if
  persistence gating regresses.
- Restored terminal tabs launch fresh shells; users must not confuse this with
  process or scrollback restoration.

## Success Criteria

- Packaged app restores workspace layout across relaunch.
- Debug validation with `CONDUCTOR_DISABLE_PERSISTENCE=1` remains isolated.
- `swift build --disable-build-manifest-caching --product Conductor` passes.
- `swift run ConductorModelCheck` passes.
- No terminal content snapshot files are created.

