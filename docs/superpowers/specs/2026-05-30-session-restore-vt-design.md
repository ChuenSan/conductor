# Garble-Free Session Restore (VT) + ConductorCore Test Net — Design

- **Date:** 2026-05-30
- **Status:** Approved (design); pending implementation plan
- **Scope:** Sub-project "0+A" of the Conductor-vs-cmux improvement roadmap
- **Branch:** `session-restore-vt`

## 1. Context & Motivation

Conductor restores prior-session terminal content across restarts, but the restored
history is **garbled and de-colored**. Root causes in the current path
(`TerminalSurface.swift:385-456`, `ConductorWindowModel.swift:3222-3231`):

1. **Color loss** — capture uses `ghostty_surface_read_text` (`GHOSTTY_POINT_SCREEN`),
   which returns plain, de-styled UTF-8. All SGR/bold/italic/color is dropped.
2. **Unsafe truncation** — over `maxBytes` it does `String(decoding: result.utf8.suffix(maxBytes), as: UTF8.self)`,
   a raw byte-suffix cut that can slice a multi-byte codepoint (→ visible `U+FFFD`)
   or an escape sequence.
3. **Marker pollution** — replay injects human-readable marker lines
   (`──── 上次会话 (只读历史) ────`). There is no consumer that strips them, so they
   are permanently baked into scrollback and **re-persisted on the next capture**,
   compounding every restart.
4. **Wide/CJK misalignment** — replay re-measures column width via `process_output`;
   any width disagreement (emoji, ambiguous-width, combining/ZWJ) shifts the rest of
   the row.
5. **No full SGR reset** — only a muted `ESC[2m..ESC[0m` wraps the markers, not the
   whole payload; stray escape bytes can leak color/mode into the live prompt.

### How cmux avoids garble (verified)

cmux serializes screen+scrollback to **VT/ANSI escape sequences** (preserving SGR,
cursor, wide-char layout) via the ghostty keybind action `write_screen_file:copy,vt`,
stores the raw VT bytes, and replays them so ghostty's **own VT parser** re-renders
the exact bytes. The exact-bytes round-trip is why it never garbles. (cmux replays
through the PTY via shell-integration `cat`; see Decision D1 for our variant.)

### Feasibility (verified against the vendored binary)

Conductor's vendored `GhosttyKit.xcframework` **already supports** this with no
rebuild: `ghostty_surface_binding_action` is declared at
`Vendor/GhosttyKit.xcframework/macos-arm64_x86_64/Headers/ghostty.h:1174`, and the
literal `write_screen_file:copy,vt` (plus `html`/`plain` variants) is compiled into
`libghostty-internal.a`. Conductor and cmux share the same cmux fork of libghostty.
The supporting plumbing already exists: `performBindingAction`
(`TerminalSurface.swift:458-463`), clipboard write callback routing `copy` to
`NSPasteboard.general` (`GhosttyAppRuntime.swift:81-90`, synchronous), and per-surface
env injection (`TerminalSurface.swift:138-162`).

## 2. Decisions

- **D1 — Replay path: Option B (Swift direct).** Feed the VT bytes back via
  `ghostty_surface_process_output` (the program-output path; inert, never executed),
  with ANSI-safe processing in Swift. No shell-integration fork to maintain.
  Capture/storage format is identical to the PTY-`cat` variant, so a future upgrade to
  Option A (true cmux parity at cursor/scroll-region edges) only swaps the replay tail.
- **D2 — No marker injection (cmux-style).** Do not write any "previous session"
  marker into the terminal grid. VT replay keeps original colors, so old history reads
  as real scrollback. A future visual divider, if wanted, must be a SwiftUI overlay
  (never written into the grid).
- **D3 — Test net first.** Wire a real `ConductorCoreTests` target before/while
  building A, and TDD the new pure logic. Migrate the existing `ConductorModelCheck`
  assertions into Swift Testing in parallel (subagent), keeping the
  `ConductorModelCheck` executable as the smoke gate.

## 3. Goals & Success Criteria

1. `swift test` runs and covers workspace invariants + the new scrollback logic.
2. Restored history has **original color**, **no `U+FFFD`**, **no marker lines**, and
   **no wide/CJK misalignment**.
3. VT export failure degrades gracefully to plain-text capture (no crash, no stall).
4. Capture never corrupts the user's clipboard (saved and restored around the action).

## 4. Architecture

Pure string logic lives in `ConductorCore` (unit-testable); the libghostty-bound layer
is a thin I/O shim that delegates all sanitization to the core.

```
ConductorCore (pure value types, unit-tested)
  TerminalScrollbackSanitizer (new)
    • truncate(maxLines:maxBytes:)   ANSI/UTF-8-safe (no mid-codepoint / mid-CSI cut)
    • normalizeLineEndings(_:)       idempotent bare \n → \r\n
    • wrapForReplay(_:)              leading + trailing ESC[0m
    • prepareForReplay(maxLines:maxBytes:)  composition used by the replay layer

Conductor app (libghostty boundary, integration-verified — not unit-tested)
  TerminalSurface.capturedScrollbackVT()   capture: copy,vt → pasteboard path → read
                                            file → delete temp → restore pasteboard
  TerminalSurface.replayPendingSnapshot()  replay: no markers; process_output of
                                            TerminalScrollbackSanitizer.prepareForReplay
  ConductorWindowModel.captureTerminalSnapshots  VT capture, fallback to plain text
```

## 5. Components

### 5.1 `TerminalScrollbackSanitizer` (new — `ConductorCore`, pure, TDD)

The heart of "garble-free". All logic here is pure and fully unit-tested.

- `truncate(_ text: String, maxLines: Int, maxBytes: Int) -> String` — keep the last
  `maxLines` lines / `maxBytes` bytes, but never cut inside a multi-byte codepoint or a
  CSI escape sequence. Port cmux's `ansiSafeTruncationStart` / `csiFinalByteIndex`
  boundary logic (`SessionPersistence.swift:60-117`): if a truncation point lands inside
  a CSI sequence, advance past its final byte.
- `normalizeLineEndings(_ text: String) -> String` — idempotently convert bare `\n` to
  `\r\n` (do not double-CR an existing `\r\n`; leave a lone `\r`). Required because
  Option B's `process_output` does not get the tty's ONLCR post-processing that the
  PTY path would.
- `wrapForReplay(_ text: String) -> String` — prefix and suffix a full `ESC[0m` reset so
  stray escape state cannot leak into the live prompt.
- `prepareForReplay(_ text: String, maxLines: Int, maxBytes: Int) -> String` —
  `truncate` → `normalizeLineEndings` → `wrapForReplay`.

### 5.2 `TerminalSurface` (changed — app layer, thin binding)

- **New** `capturedScrollbackVT() -> String?`:
  1. Snapshot `NSPasteboard.general` (save items to restore later).
  2. `performBindingAction("write_screen_file:copy,vt")`.
  3. Read the path string from `NSPasteboard.general`; normalize via a port of cmux's
     `normalizedExportedScreenPath` (`TerminalController.swift:755-765`) — accepts a
     `file://` URL or an absolute path.
  4. Read the temp file's raw VT bytes (valid UTF-8).
  5. Delete the temp file iff it lives under the system temp dir (port
     `shouldRemoveExportedScreenFile`, `TerminalController.swift:767-783`).
  6. **Always** restore the saved pasteboard (use `defer`).
  7. Return `nil` on any failure.
- `replayPendingSnapshot`: remove the muted header/footer injection and the blanket
  `\n→\r\n`; replay `TerminalScrollbackSanitizer.prepareForReplay(snapshot, ...)` via
  `process_output`. Still inert / read-only.

### 5.3 `ConductorWindowModel.captureTerminalSnapshots` (changed — `:3222-3231`)

Try `capturedScrollbackVT()`; on `nil`, fall back to `capturedScrollbackText()` (mirrors
cmux's `allowVTExport` fallback). Apply `truncate` at capture time so sidecars stay
small. Capture stays on the main actor (libghostty surface access requires it); the
off-thread/line-bound capture optimization is deferred to the performance sub-project.

### 5.4 `WorkspacePersistence` (small change)

Keep the per-terminal sidecar mechanism (VT is valid UTF-8; reuse `.txt`). Add a small
format marker so new VT snapshots are distinguishable from pre-upgrade plain-text ones
(old ones still render, just without color).

## 6. Test Net (item 0)

- Add `.testTarget(name: "ConductorCoreTests", dependencies: ["ConductorCore"])` to
  `Package.swift`.
- New `Tests/ConductorCoreTests/TerminalScrollbackSanitizerTests.swift` — **written
  first (red → green)**: codepoint-boundary truncation, CSI-boundary truncation,
  idempotent line endings, full SGR reset wrap, empty input, byte truncation with
  emoji/CJK.
- Migrate the ~50 `ConductorModelCheck` `check*` assertions into Swift Testing
  (`require` → `#expect`), locking in existing invariant coverage. Keep the
  `ConductorModelCheck` executable as the smoke gate. (Parallelizable to a subagent.)

## 7. Error Handling & Edge Cases

- VT export failure or missing/invalid pasteboard path → fall back to plain-text capture
  (degrade, never crash).
- Capture **always** restores the user's pasteboard via `defer`.
- `truncate` never throws; empty result → `nil`.
- Temp file deleted only when confirmed under the system temp directory.

## 8. Out of Scope / Deferred

- **Option A (PTY `cat` replay)** — possible later upgrade; capture/storage unchanged.
- **Off-thread / line-bounded capture at quit** — belongs to the performance sub-project.
- **Visual "old session" divider** — only as a SwiftUI overlay, future work.
- **Stash reconciliation** — the stashed uncommitted work's "off-thread persistence" is
  good (cherry-pick into the performance sub-project); its "marker filtering" is
  superseded by D2 and should be dropped.

## 9. Files Touched

| File | Change |
| --- | --- |
| `Apps/Conductor/Package.swift` | add `ConductorCoreTests` testTarget |
| `Apps/Conductor/Sources/ConductorCore/Workspace/TerminalScrollbackSanitizer.swift` | new — pure sanitization logic |
| `Apps/Conductor/Tests/ConductorCoreTests/TerminalScrollbackSanitizerTests.swift` | new — TDD tests |
| `Apps/Conductor/Tests/ConductorCoreTests/WorkspaceModelTests.swift` (+ peers by theme) | migrated `ConductorModelCheck` assertions |
| `Apps/Conductor/Sources/Conductor/Terminal/TerminalSurface.swift` | `capturedScrollbackVT`, replay change, ported path helpers |
| `Apps/Conductor/Sources/Conductor/UI/ConductorWindowModel.swift` | VT capture + fallback at `:3222-3231` |
| `Apps/Conductor/Sources/Conductor/Shared/WorkspacePersistence.swift` | sidecar format marker |

## 10. Verification Plan

- `swift test` (sanitizer + migrated invariants) green.
- `swift build` clean; `swift run ConductorModelCheck` still passes.
- Manual/integration: run the app, produce colored + CJK + wide-char output, quit,
  relaunch, confirm restored history is colored, aligned, marker-free, and `U+FFFD`-free.
