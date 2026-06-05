# Workspace Restore Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use
> `superpowers:executing-plans` or equivalent task-by-task execution. Steps use
> checkbox (`- [ ]`) syntax for tracking.

**Goal:** Restore compact Conductor workspace/window state across packaged app
launches without restoring terminal output, scrollback, VT bytes, or shell
processes.

**Spec:** `docs/superpowers/specs/2026-06-05-workspace-restore-design.md`

**Working directory for commands:** `Apps/Conductor`

**Validation commands:**

```bash
swift build --disable-build-manifest-caching --product Conductor
swift run ConductorModelCheck
```

---

## File Structure

| File | Responsibility |
| --- | --- |
| `Apps/Conductor/Sources/Conductor/Shared/WorkspacePersistence.swift` | Add sanitized `load()` for YAML and legacy JSON |
| `Apps/Conductor/Sources/Conductor/UI/ConductorWindowModel.swift` | Initialize from persisted state before defaulting |
| `Apps/Conductor/Sources/ConductorModelCheck/main.swift` | Add regression checks if current model-check helpers can cover persistence |
| `Apps/Conductor/README.md` | Keep docs accurate: workspace restore yes, terminal content restore no |

---

## Task 1: Add Persistence Loading

**Files:**
- Modify: `Apps/Conductor/Sources/Conductor/Shared/WorkspacePersistence.swift`

- [x] **Step 1: Add `load()`**

Add a public instance method:

```swift
func load() -> PersistedWindowState?
```

Behavior:

- Return `nil` when persistence is disabled.
- If `CONDUCTOR_RESET_STATE=1`, call `reset()` and return `nil`.
- Read `window-state.yaml` first.
- Fall back to legacy `window-state.json`.
- Decode YAML with `YAMLDecoder`.
- Decode JSON with `JSONDecoder`.
- Return sanitized state only.

- [x] **Step 2: Add private decode helpers**

Add:

```swift
private func loadState() -> PersistedWindowState?
private func decodeState(at url: URL) -> PersistedWindowState?
```

Keep the helpers private to `WorkspacePersistence`.

- [x] **Step 3: Sanitize restored state**

Sanitize before returning:

- `workspaces.map(sanitizedWorkspace).filter(isValid)`
- selected workspace fallback
- `sanitizedWebTabs`
- `sanitizedFileTabs`
- `sanitizedWorkspaceContentStates`

Return `nil` when no valid workspace remains.

- [x] **Step 4: Avoid terminal snapshot APIs**

Do not add back any of:

- `saveTerminalSnapshot`
- `loadTerminalSnapshot`
- `removeTerminalSnapshot`
- `pruneTerminalSnapshots`
- session journal APIs
- VT sidecar file APIs

---

## Task 2: Initialize Window Model From Restored State

**Files:**
- Modify: `Apps/Conductor/Sources/Conductor/UI/ConductorWindowModel.swift`

- [x] **Step 1: Load persisted state at the top of `init()`**

Replace the unconditional default workspace initialization with:

```swift
let restoredState = persistence.load()
let initialWorkspace = restoredState?.workspaces.first {
    $0.id == restoredState?.selectedWorkspaceID
} ?? restoredState?.workspaces.first ?? WorkspaceState()
```

Initialize:

- `workspaces`
- `selectedWorkspaceID`
- `workspace`
- `theme`
- `appearance`

from restored state when available.

- [x] **Step 2: Restore workspace content runtime state**

Map each `PersistedWorkspaceContentState` into `WorkspaceContentRuntimeState`.

Rules:

- Restore web tab metadata directly.
- Rebuild file tabs with `ConductorWorkspaceFileTab(fileURL:rootURL:)`.
- Keep `dirtyFileTabIDs` and `externallyChangedFileTabIDs` empty.
- Validate selected content with `validatedWorkspaceContentSelection`.

- [x] **Step 3: Apply selected workspace content**

After `workspaceContentStatesByWorkspaceID` is initialized, set:

- `workspaceWebTabs`
- `workspaceFileTabs`
- `dirtyWorkspaceFileTabIDs`
- `externallyChangedWorkspaceFileTabIDs`
- `selectedWorkspaceContentTabID`

for `selectedWorkspaceID`.

If selection is invalid, fall back to the selected terminal tab.

- [x] **Step 4: Preserve default path**

When `persistence.load()` returns nil, keep today's default startup behavior.

- [x] **Step 5: Prevent startup overwrite**

Do not call `persist()` from `init()`.

Keep metadata refresh and runtime polling startup after restored state is applied.

---

## Task 3: Add Regression Coverage

**Files:**
- Modify: `Apps/Conductor/Sources/ConductorModelCheck/main.swift`
- Or add Swift tests if easier with the current test harness.

- [ ] **Step 1: Add restore fixture helper**

Deferred: `WorkspacePersistence` currently lives in the app executable target,
while `ConductorModelCheck` and `ConductorCoreTests` only depend on
`ConductorCore`. Adding direct persistence coverage would require a target
structure change or moving the persistence model into a reusable library.

Use a temporary `CONDUCTOR_STATE_PATH` file or a direct
`WorkspacePersistence` initializer if the API supports it.

The fixture should write a compact persisted state with:

- two workspaces
- selected second workspace
- at least one split pane
- a web tab
- a file tab pointing at a temporary file

- [ ] **Step 2: Assert load behavior**

Assert:

- two workspaces load
- selected workspace is the second workspace
- split tree is coherent
- selected terminal content is valid
- file tab survives when the file exists
- web tab loading/progress is cleared

- [ ] **Step 3: Assert reset behavior**

With `CONDUCTOR_RESET_STATE=1`, loading returns nil and removes state.

---

## Task 4: Build And Manual Validation

- [x] **Step 1: Build**

```bash
cd Apps/Conductor
swift build --disable-build-manifest-caching --product Conductor
```

- [x] **Step 2: Model check**

```bash
cd Apps/Conductor
swift run ConductorModelCheck
```

- [ ] **Step 3: Isolated manual restore**

Use a temporary state path:

```bash
CONDUCTOR_STATE_PATH=/tmp/conductor-workspace-restore.yaml \
./Scripts/run-conductor.sh
```

Create workspaces/splits/tabs, quit, relaunch with the same state path, and
confirm restore.

- [ ] **Step 4: Packaged app restore**

Run the packaged `/Applications/Conductor.app` without
`CONDUCTOR_DISABLE_PERSISTENCE`.

Confirm:

- workspace list returns
- selected workspace returns
- splits return
- file/web tabs return
- no terminal output returns
- no `session-journal.ndjson` or `session-snapshots/` appears

---

## Task 5: Commit

- [ ] **Step 1: Review diff**

```bash
git diff --stat
git diff -- Apps/Conductor/Sources/Conductor/Shared/WorkspacePersistence.swift
git diff -- Apps/Conductor/Sources/Conductor/UI/ConductorWindowModel.swift
```

- [ ] **Step 2: Commit**

```bash
git add \
  docs/superpowers/specs/2026-06-05-workspace-restore-design.md \
  docs/superpowers/plans/2026-06-05-workspace-restore.md \
  Apps/Conductor/Sources/Conductor/Shared/WorkspacePersistence.swift \
  Apps/Conductor/Sources/Conductor/UI/ConductorWindowModel.swift \
  Apps/Conductor/Sources/ConductorModelCheck/main.swift

git commit -m "Restore compact workspace state on launch"
```
