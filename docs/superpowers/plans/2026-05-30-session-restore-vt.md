# Garble-Free Session Restore (VT) + ConductorCore Test Net — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Restore prior-session terminal content with original color and no garble by capturing scrollback as VT/ANSI bytes, sanitizing it with a pure, unit-tested `ConductorCore` type, and replaying it via `process_output` — and wire a real `ConductorCoreTests` target so this (and future work) is test-driven.

**Architecture:** All string processing lives in a new pure `TerminalScrollbackSanitizer` in `ConductorCore` (fully unit-tested). The libghostty-bound layer (`TerminalSurface`) is a thin I/O shim: it exports VT via the `write_screen_file:copy,vt` keybind action (already compiled into the vendored GhosttyKit), reads the temp file off the pasteboard, and replays the sanitizer's output. Pure path helpers also move to `ConductorCore` so they are tested too.

**Tech Stack:** Swift 6, SwiftPM, Swift Testing (`import Testing`), AppKit (`NSPasteboard`), vendored GhosttyKit (libghostty C API).

**Spec:** `docs/superpowers/specs/2026-05-30-session-restore-vt-design.md`

**Working directory for all commands:** `Apps/Conductor`

> **Running tests on this machine:** it is Command Line Tools-only (no Xcode/XCTest). Plain `swift test` cannot load Swift Testing at runtime. **Always run tests via `./Scripts/swift-test.sh`** (commits the rpath flags). `swift build` and `swift run ConductorModelCheck` work normally. The commands below already use the wrapper.

---

## File Structure

| File | Responsibility |
| --- | --- |
| `Apps/Conductor/Package.swift` | declare the `ConductorCoreTests` test target |
| `Apps/Conductor/Sources/ConductorCore/Shared/TerminalScrollbackSanitizer.swift` | **new** — pure: ANSI/UTF-8-safe truncation, idempotent line endings, replay wrapping |
| `Apps/Conductor/Sources/ConductorCore/Shared/ExportedScreenPath.swift` | **new** — pure: normalize the exported-screen path, temp-dir safety check |
| `Apps/Conductor/Tests/ConductorCoreTests/TerminalScrollbackSanitizerTests.swift` | **new** — TDD tests for the sanitizer |
| `Apps/Conductor/Tests/ConductorCoreTests/ExportedScreenPathTests.swift` | **new** — TDD tests for path helpers |
| `Apps/Conductor/Tests/ConductorCoreTests/WorkspaceModelTests.swift` (+ peers) | **new** — migrated `ConductorModelCheck` assertions |
| `Apps/Conductor/Sources/Conductor/Terminal/TerminalSurface.swift` | add `capturedScrollbackVT()`; rewrite replay to use the sanitizer, drop markers |
| `Apps/Conductor/Sources/Conductor/UI/ConductorWindowModel.swift` | capture VT with plain-text fallback |
| `Apps/Conductor/Sources/Conductor/Shared/WorkspacePersistence.swift` | store/load VT snapshots under `.vt`, keep `.txt` legacy read |

---

## Task 1: Wire the ConductorCoreTests target

**Files:**
- Modify: `Apps/Conductor/Package.swift`
- Test: `Apps/Conductor/Tests/ConductorCoreTests/SanityTests.swift`

- [ ] **Step 1: Write the failing test**

Create `Apps/Conductor/Tests/ConductorCoreTests/SanityTests.swift`:

```swift
import Testing
@testable import ConductorCore

@Test func newWorkspaceHasOnePane() {
    let workspace = WorkspaceState()
    #expect(workspace.root.leaves.count == 1)
    #expect(workspace.focusedPane?.tabs.count == 1)
}
```

- [ ] **Step 2: Run it to verify the target does not exist yet**

Run: `cd Apps/Conductor && ./Scripts/swift-test.sh --filter SanityTests`
Expected: FAIL — SwiftPM reports no test target / nothing to test (the target is not declared yet).

- [ ] **Step 3: Declare the test target**

In `Apps/Conductor/Package.swift`, add this entry to the end of the `targets:` array (after the `ConductorModelCheck` executable target):

```swift
        ,
        .testTarget(
            name: "ConductorCoreTests",
            dependencies: ["ConductorCore"]
        )
```

(Place the leading comma correctly: the previous target's closing `)` must be followed by a comma before this entry. The final array element does not need a trailing comma, but Swift allows one.)

- [ ] **Step 4: Run the test to verify it passes**

Run: `cd Apps/Conductor && ./Scripts/swift-test.sh --filter SanityTests`
Expected: PASS — `1 test passed`.

- [ ] **Step 5: Commit**

```bash
git add Apps/Conductor/Package.swift Apps/Conductor/Tests/ConductorCoreTests/SanityTests.swift
git commit -m "test: wire ConductorCoreTests target

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 2: `TerminalScrollbackSanitizer.truncate` — ANSI/UTF-8-safe truncation

**Files:**
- Create: `Apps/Conductor/Sources/ConductorCore/Shared/TerminalScrollbackSanitizer.swift`
- Test: `Apps/Conductor/Tests/ConductorCoreTests/TerminalScrollbackSanitizerTests.swift`

- [ ] **Step 1: Write the failing tests**

Create `Apps/Conductor/Tests/ConductorCoreTests/TerminalScrollbackSanitizerTests.swift`:

```swift
import Testing
@testable import ConductorCore

@Test func truncateKeepsLastLines() {
    let input = (1...10).map { "line\($0)" }.joined(separator: "\n")
    let result = TerminalScrollbackSanitizer.truncate(input, maxLines: 3, maxBytes: 1_000_000)
    #expect(result == "line8\nline9\nline10")
}

@Test func truncateNeverSplitsACodepoint() {
    // 200 CJK chars, each 3 UTF-8 bytes. Cap at 90 bytes -> must land on a char boundary.
    let input = String(repeating: "中", count: 200)
    let result = TerminalScrollbackSanitizer.truncate(input, maxLines: 1_000, maxBytes: 90)
    #expect(!result.unicodeScalars.contains("\u{FFFD}"))
    #expect(result.utf8.count <= 90)
    #expect(result.allSatisfy { $0 == "中" })
}

@Test func truncateDropsPartialFirstLineAtByteBoundary() {
    // Two lines; cap below the first line's length forces a mid-first-line cut,
    // which must be resolved by dropping to the start of the next full line.
    let input = "aaaaaaaaaaERASEME\nkeptline"
    let result = TerminalScrollbackSanitizer.truncate(input, maxLines: 1_000, maxBytes: 12)
    #expect(result == "keptline")
}

@Test func truncateReturnsEmptyWhenNothingSurvivesByteCap() {
    let input = String(repeating: "x", count: 100) // single line, no newline
    let result = TerminalScrollbackSanitizer.truncate(input, maxLines: 1_000, maxBytes: 10)
    #expect(result == "")
}
```

- [ ] **Step 2: Run to verify failure**

Run: `cd Apps/Conductor && ./Scripts/swift-test.sh --filter TerminalScrollbackSanitizerTests`
Expected: FAIL — `TerminalScrollbackSanitizer` is undefined.

- [ ] **Step 3: Implement `truncate`**

Create `Apps/Conductor/Sources/ConductorCore/Shared/TerminalScrollbackSanitizer.swift`:

```swift
import Foundation

/// Pure helpers that make prior-session scrollback safe to repaint into a fresh
/// terminal surface without garbling: byte- and escape-safe truncation,
/// idempotent line-ending normalization, and a full SGR reset wrap.
///
/// Capture and replay are byte streams of VT/ANSI escape sequences (from
/// libghostty's `write_screen_file:copy,vt` export), so every transform here
/// must preserve escape-sequence and UTF-8 codepoint boundaries.
public enum TerminalScrollbackSanitizer {
    /// Keeps the last `maxLines` lines and at most `maxBytes` bytes, never cutting
    /// inside a multi-byte codepoint or a line's escape sequence.
    public static func truncate(_ text: String, maxLines: Int, maxBytes: Int) -> String {
        // Line cap first: splitting on "\n" (a single 0x0A byte) is always safe.
        var lines = text.components(separatedBy: "\n")
        if lines.count > maxLines {
            lines = Array(lines.suffix(maxLines))
        }
        let lineCapped = lines.joined(separator: "\n")
        guard lineCapped.utf8.count > maxBytes else { return lineCapped }
        return safeByteSuffix(lineCapped, maxBytes: maxBytes)
    }

    /// Returns the last `maxBytes` bytes, advanced forward to (a) the next UTF-8
    /// leading byte and (b) the start of the next full line, so the suffix never
    /// begins mid-codepoint or inside a partial escape sequence.
    static func safeByteSuffix(_ text: String, maxBytes: Int) -> String {
        let bytes = Array(text.utf8)
        guard bytes.count > maxBytes else { return text }
        var start = bytes.count - maxBytes
        // (a) Skip UTF-8 continuation bytes (0b10xxxxxx).
        while start < bytes.count, (bytes[start] & 0xC0) == 0x80 {
            start += 1
        }
        // (b) Skip the (possibly partial) first line: resume after the next newline.
        if let newline = bytes[start...].firstIndex(of: 0x0A) {
            start = newline + 1
        }
        guard start < bytes.count else { return "" }
        return String(decoding: bytes[start...], as: UTF8.self)
    }
}
```

- [ ] **Step 4: Run to verify pass**

Run: `cd Apps/Conductor && ./Scripts/swift-test.sh --filter TerminalScrollbackSanitizerTests`
Expected: PASS — 4 tests pass.

- [ ] **Step 5: Commit**

```bash
git add Apps/Conductor/Sources/ConductorCore/Shared/TerminalScrollbackSanitizer.swift Apps/Conductor/Tests/ConductorCoreTests/TerminalScrollbackSanitizerTests.swift
git commit -m "feat: ANSI/UTF-8-safe scrollback truncation

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 3: `normalizeLineEndings` — idempotent bare `\n` → `\r\n`

**Files:**
- Modify: `Apps/Conductor/Sources/ConductorCore/Shared/TerminalScrollbackSanitizer.swift`
- Test: `Apps/Conductor/Tests/ConductorCoreTests/TerminalScrollbackSanitizerTests.swift`

- [ ] **Step 1: Write the failing tests**

Append to `TerminalScrollbackSanitizerTests.swift`:

```swift
@Test func normalizeAddsCarriageReturnToBareNewline() {
    #expect(TerminalScrollbackSanitizer.normalizeLineEndings("a\nb") == "a\r\nb")
}

@Test func normalizeIsIdempotentForCRLF() {
    // "\r\n" is a single Swift Character, so it is never matched as a bare "\n".
    let crlf = "a\r\nb"
    #expect(TerminalScrollbackSanitizer.normalizeLineEndings(crlf) == crlf)
    #expect(TerminalScrollbackSanitizer.normalizeLineEndings(crlf) ==
            TerminalScrollbackSanitizer.normalizeLineEndings(
                TerminalScrollbackSanitizer.normalizeLineEndings(crlf)))
}

@Test func normalizeLeavesLoneCarriageReturn() {
    #expect(TerminalScrollbackSanitizer.normalizeLineEndings("a\rb") == "a\rb")
}
```

- [ ] **Step 2: Run to verify failure**

Run: `cd Apps/Conductor && ./Scripts/swift-test.sh --filter TerminalScrollbackSanitizerTests`
Expected: FAIL — `normalizeLineEndings` is undefined.

- [ ] **Step 3: Implement `normalizeLineEndings`**

Add this method inside the `TerminalScrollbackSanitizer` enum in `TerminalScrollbackSanitizer.swift`:

```swift
    /// Converts bare line-feeds to CRLF so each line returns to column 0 under the
    /// `process_output` replay path (which, unlike a real tty, does not apply ONLCR).
    /// Idempotent: an existing "\r\n" is one Swift `Character` and is never matched
    /// as a bare "\n", and a lone "\r" is left untouched.
    public static func normalizeLineEndings(_ text: String) -> String {
        var out = String()
        out.reserveCapacity(text.count + 16)
        for character in text {
            if character == "\n" {
                out.append("\r\n")
            } else {
                out.append(character)
            }
        }
        return out
    }
```

- [ ] **Step 4: Run to verify pass**

Run: `cd Apps/Conductor && ./Scripts/swift-test.sh --filter TerminalScrollbackSanitizerTests`
Expected: PASS — all sanitizer tests pass.

- [ ] **Step 5: Commit**

```bash
git add Apps/Conductor/Sources/ConductorCore/Shared/TerminalScrollbackSanitizer.swift Apps/Conductor/Tests/ConductorCoreTests/TerminalScrollbackSanitizerTests.swift
git commit -m "feat: idempotent CRLF normalization for replay

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 4: `wrapForReplay` + `prepareForReplay`

**Files:**
- Modify: `Apps/Conductor/Sources/ConductorCore/Shared/TerminalScrollbackSanitizer.swift`
- Test: `Apps/Conductor/Tests/ConductorCoreTests/TerminalScrollbackSanitizerTests.swift`

- [ ] **Step 1: Write the failing tests**

Append to `TerminalScrollbackSanitizerTests.swift`:

```swift
@Test func wrapAddsLeadingAndTrailingReset() {
    let wrapped = TerminalScrollbackSanitizer.wrapForReplay("hi")
    #expect(wrapped == "\u{1B}[0mhi\u{1B}[0m")
}

@Test func prepareComposesTruncateNormalizeAndWrap() {
    let input = "a\nb\nc"
    let result = TerminalScrollbackSanitizer.prepareForReplay(input, maxLines: 2, maxBytes: 1_000)
    // last 2 lines -> "b\nc"; CRLF -> "b\r\nc"; wrapped in resets.
    #expect(result == "\u{1B}[0mb\r\nc\u{1B}[0m")
}

@Test func prepareReturnsBareResetsForEmptyInput() {
    #expect(TerminalScrollbackSanitizer.prepareForReplay("", maxLines: 100, maxBytes: 100)
            == "\u{1B}[0m\u{1B}[0m")
}
```

- [ ] **Step 2: Run to verify failure**

Run: `cd Apps/Conductor && ./Scripts/swift-test.sh --filter TerminalScrollbackSanitizerTests`
Expected: FAIL — `wrapForReplay` / `prepareForReplay` undefined.

- [ ] **Step 3: Implement both methods**

Add inside the `TerminalScrollbackSanitizer` enum:

```swift
    /// Brackets the payload with a full SGR reset on both sides so no stray color or
    /// mode state survives into (or leaks out of) the replayed history.
    public static func wrapForReplay(_ text: String) -> String {
        let reset = "\u{1B}[0m"
        return reset + text + reset
    }

    /// The single entry point the replay layer calls: truncate, normalize, wrap.
    public static func prepareForReplay(
        _ text: String,
        maxLines: Int = 400,
        maxBytes: Int = 128 * 1024
    ) -> String {
        wrapForReplay(normalizeLineEndings(truncate(text, maxLines: maxLines, maxBytes: maxBytes)))
    }
```

- [ ] **Step 4: Run to verify pass**

Run: `cd Apps/Conductor && ./Scripts/swift-test.sh --filter TerminalScrollbackSanitizerTests`
Expected: PASS — all sanitizer tests pass.

- [ ] **Step 5: Commit**

```bash
git add Apps/Conductor/Sources/ConductorCore/Shared/TerminalScrollbackSanitizer.swift Apps/Conductor/Tests/ConductorCoreTests/TerminalScrollbackSanitizerTests.swift
git commit -m "feat: prepareForReplay composes the replay pipeline

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 5: `ExportedScreenPath` — pure path helpers for VT capture

**Files:**
- Create: `Apps/Conductor/Sources/ConductorCore/Shared/ExportedScreenPath.swift`
- Test: `Apps/Conductor/Tests/ConductorCoreTests/ExportedScreenPathTests.swift`

- [ ] **Step 1: Write the failing tests**

Create `Apps/Conductor/Tests/ConductorCoreTests/ExportedScreenPathTests.swift`:

```swift
import Foundation
import Testing
@testable import ConductorCore

@Test func normalizesFileURLToPath() {
    #expect(ExportedScreenPath.normalized("file:///tmp/screen.vt") == "/tmp/screen.vt")
}

@Test func passesThroughAbsolutePath() {
    #expect(ExportedScreenPath.normalized("/var/folders/x/screen.vt") == "/var/folders/x/screen.vt")
}

@Test func trimsWhitespace() {
    #expect(ExportedScreenPath.normalized("  /tmp/a.vt \n") == "/tmp/a.vt")
}

@Test func rejectsNonAbsoluteOrEmpty() {
    #expect(ExportedScreenPath.normalized("not-a-path") == nil)
    #expect(ExportedScreenPath.normalized("   ") == nil)
    #expect(ExportedScreenPath.normalized(nil) == nil)
}

@Test func temporaryDirectoryGuard() {
    let temp = URL(fileURLWithPath: "/var/folders/tmp", isDirectory: true)
    #expect(ExportedScreenPath.isUnderTemporaryDirectory(
        URL(fileURLWithPath: "/var/folders/tmp/screen.vt"), temporaryDirectory: temp))
    #expect(!ExportedScreenPath.isUnderTemporaryDirectory(
        URL(fileURLWithPath: "/Users/me/screen.vt"), temporaryDirectory: temp))
}
```

- [ ] **Step 2: Run to verify failure**

Run: `cd Apps/Conductor && ./Scripts/swift-test.sh --filter ExportedScreenPathTests`
Expected: FAIL — `ExportedScreenPath` undefined.

- [ ] **Step 3: Implement the helpers**

Create `Apps/Conductor/Sources/ConductorCore/Shared/ExportedScreenPath.swift`:

```swift
import Foundation

/// Pure helpers for handling the temp-file path that libghostty's
/// `write_screen_file:copy,…` action places on the pasteboard.
public enum ExportedScreenPath {
    /// Normalizes a pasteboard string to a filesystem path: accepts a `file://`
    /// URL or an absolute path, rejects anything else.
    public static func normalized(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if let url = URL(string: trimmed), url.isFileURL, !url.path.isEmpty {
            return url.path
        }
        return trimmed.hasPrefix("/") ? trimmed : nil
    }

    /// True only when `fileURL` lives under the system temporary directory, so the
    /// caller can safely delete the export without ever touching a user file.
    public static func isUnderTemporaryDirectory(
        _ fileURL: URL,
        temporaryDirectory: URL = FileManager.default.temporaryDirectory
    ) -> Bool {
        let file = fileURL.standardizedFileURL
        let temp = temporaryDirectory.standardizedFileURL
        return file.path.hasPrefix(temp.path + "/")
    }
}
```

- [ ] **Step 4: Run to verify pass**

Run: `cd Apps/Conductor && ./Scripts/swift-test.sh --filter ExportedScreenPathTests`
Expected: PASS — 5 tests pass.

- [ ] **Step 5: Commit**

```bash
git add Apps/Conductor/Sources/ConductorCore/Shared/ExportedScreenPath.swift Apps/Conductor/Tests/ConductorCoreTests/ExportedScreenPathTests.swift
git commit -m "feat: pure exported-screen path helpers

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 6: `TerminalSurface.capturedScrollbackVT()` — VT export capture

This is a libghostty-bound I/O shim; it is not unit-tested (verified manually in Task 9). It reuses the existing `performBindingAction` wrapper and the pure helpers from Tasks 2 and 5.

**Files:**
- Modify: `Apps/Conductor/Sources/Conductor/Terminal/TerminalSurface.swift`

- [ ] **Step 1: Confirm `ConductorCore` is imported**

Run: `cd Apps/Conductor && head -20 Sources/Conductor/Terminal/TerminalSurface.swift`
Expected: an `import ConductorCore` line near the top. If it is absent, add `import ConductorCore` after the existing `import` lines.

- [ ] **Step 2: Add `capturedScrollbackVT()`**

In `TerminalSurface.swift`, insert this method immediately after `capturedScrollbackText(...)` (it ends at line ~422, just before `setSnapshotReplay`):

```swift
    /// Captures the on-screen scrollback as a VT/ANSI byte stream (colors, cursor,
    /// wide-char layout preserved) via libghostty's `write_screen_file:copy,vt`
    /// action, which writes a temp file and puts its path on the pasteboard. The
    /// user's pasteboard is saved and restored around the call. Returns nil on any
    /// failure so the caller can fall back to plain-text capture.
    func capturedScrollbackVT(maxLines: Int = 400, maxBytes: Int = 128 * 1024) -> String? {
        guard surface != nil else { return nil }
        let pasteboard = NSPasteboard.general

        let savedItems: [NSPasteboardItem] = (pasteboard.pasteboardItems ?? []).map { item in
            let copy = NSPasteboardItem()
            for type in item.types {
                if let data = item.data(forType: type) {
                    copy.setData(data, forType: type)
                }
            }
            return copy
        }
        defer {
            pasteboard.clearContents()
            if !savedItems.isEmpty {
                pasteboard.writeObjects(savedItems)
            }
        }

        pasteboard.clearContents()
        guard performBindingAction("write_screen_file:copy,vt") else { return nil }
        guard let raw = pasteboard.string(forType: .string),
              let path = ExportedScreenPath.normalized(raw) else { return nil }

        let fileURL = URL(fileURLWithPath: path)
        defer {
            if ExportedScreenPath.isUnderTemporaryDirectory(fileURL) {
                try? FileManager.default.removeItem(at: fileURL)
            }
        }
        guard let data = try? Data(contentsOf: fileURL), !data.isEmpty else { return nil }

        let text = TerminalScrollbackSanitizer.truncate(
            String(decoding: data, as: UTF8.self),
            maxLines: maxLines,
            maxBytes: maxBytes
        )
        return text.isEmpty ? nil : text
    }
```

- [ ] **Step 3: Verify it builds**

Run: `cd Apps/Conductor && swift build`
Expected: build succeeds (no errors).

- [ ] **Step 4: Commit**

```bash
git add Apps/Conductor/Sources/Conductor/Terminal/TerminalSurface.swift
git commit -m "feat: capture scrollback as VT bytes via write_screen_file

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 7: Replay through the sanitizer (drop markers) + capture wiring

**Files:**
- Modify: `Apps/Conductor/Sources/Conductor/Terminal/TerminalSurface.swift` (`replayPendingSnapshot`)
- Modify: `Apps/Conductor/Sources/Conductor/UI/ConductorWindowModel.swift` (`captureTerminalSnapshots`)

- [ ] **Step 1: Rewrite `replayPendingSnapshot`**

In `TerminalSurface.swift`, replace the entire `replayPendingSnapshot(into:)` method (currently lines ~432-445, which injects the muted header/footer marker lines and does the blanket `\n`→`\r\n`) with:

```swift
    private func replayPendingSnapshot(into surface: ghostty_surface_t) {
        guard let snapshot = pendingSnapshotReplay else { return }
        pendingSnapshotReplay = nil
        // Replay the prior session's VT bytes through ghostty's own parser
        // (process_output is the program-output path: inert, never executed).
        // No marker lines are injected — the restored history keeps its original
        // colors and reads as real scrollback. See spec decision D2.
        let payload = TerminalScrollbackSanitizer.prepareForReplay(snapshot)
        replayOutput(payload, into: surface)
    }
```

- [ ] **Step 2: Confirm the marker helper is gone**

Run: `cd Apps/Conductor && grep -n "上次会话\|Previous session\|会话结束\|End of previous" Sources/Conductor/Terminal/TerminalSurface.swift`
Expected: no matches (the marker strings are no longer referenced). If `ConductorLocalization` is now unused in this file, leave it — it may be used elsewhere; do not remove its import unless `swift build` warns it is unused.

- [ ] **Step 3: Point capture at VT with a plain-text fallback**

In `ConductorWindowModel.swift`, find `captureTerminalSnapshots()` (around line 3222). Replace its body with:

```swift
    private func captureTerminalSnapshots() {
        var capturedIDs = Set<TerminalID>()
        for entry in surfaceCoordinator.allSurfaces {
            // Prefer VT-format capture (color + layout); fall back to plain text.
            if let text = entry.surface.capturedScrollbackVT()
                ?? entry.surface.capturedScrollbackText() {
                persistence.saveTerminalSnapshot(id: entry.id, text: text)
                capturedIDs.insert(entry.id)
            }
        }
        persistence.pruneTerminalSnapshots(keeping: capturedIDs)
    }
```

(If your working tree shows a `retainedIDs` variant of this method instead of the `capturedIDs` one above, the stashed work is applied — it should not be on this branch. Confirm with `git status`; the branch `session-restore-vt` should have the `capturedIDs` version. Keep the structure you find, only swapping `capturedScrollbackText()` for `capturedScrollbackVT() ?? capturedScrollbackText()`.)

- [ ] **Step 4: Verify it builds**

Run: `cd Apps/Conductor && swift build`
Expected: build succeeds.

- [ ] **Step 5: Commit**

```bash
git add Apps/Conductor/Sources/Conductor/Terminal/TerminalSurface.swift Apps/Conductor/Sources/Conductor/UI/ConductorWindowModel.swift
git commit -m "feat: replay VT scrollback without marker injection

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 8: Store VT snapshots under `.vt` with `.txt` legacy fallback

**Files:**
- Modify: `Apps/Conductor/Sources/Conductor/Shared/WorkspacePersistence.swift`

- [ ] **Step 1: Update save/load/remove to use `.vt`, keeping `.txt` readable**

In `WorkspacePersistence.swift`, replace the four snapshot methods (`saveTerminalSnapshot`, `loadTerminalSnapshot`, `removeTerminalSnapshot`, `pruneTerminalSnapshots`, lines ~195-228) with:

```swift
    /// Persists a terminal's prior-session VT scrollback to a sidecar file keyed by
    /// terminal ID. New snapshots use the `.vt` extension; legacy `.txt` plain-text
    /// snapshots from before the VT upgrade are still read on load.
    func saveTerminalSnapshot(id: TerminalID, text: String) {
        guard isEnabled, let snapshotDirectoryURL, !text.isEmpty else { return }
        try? FileManager.default.createDirectory(at: snapshotDirectoryURL, withIntermediateDirectories: true)
        let url = snapshotDirectoryURL.appendingPathComponent("\(id.description).vt")
        try? text.data(using: .utf8)?.write(to: url, options: [.atomic])
        // Drop any stale plain-text sidecar so the two formats never diverge.
        try? FileManager.default.removeItem(
            at: snapshotDirectoryURL.appendingPathComponent("\(id.description).txt")
        )
    }

    func loadTerminalSnapshot(id: TerminalID) -> String? {
        guard isEnabled, let snapshotDirectoryURL else { return nil }
        for ext in ["vt", "txt"] {
            let url = snapshotDirectoryURL.appendingPathComponent("\(id.description).\(ext)")
            if let data = try? Data(contentsOf: url) {
                return String(data: data, encoding: .utf8)
            }
        }
        return nil
    }

    /// One-shot: snapshots are consumed on restore so they never stack up.
    func removeTerminalSnapshot(id: TerminalID) {
        guard let snapshotDirectoryURL else { return }
        for ext in ["vt", "txt"] {
            try? FileManager.default.removeItem(
                at: snapshotDirectoryURL.appendingPathComponent("\(id.description).\(ext)")
            )
        }
    }

    /// Drops snapshot files for terminals that no longer exist.
    func pruneTerminalSnapshots(keeping retainedIDs: Set<TerminalID>) {
        guard let snapshotDirectoryURL else { return }
        var retained = Set<String>()
        for id in retainedIDs {
            retained.insert("\(id.description).vt")
            retained.insert("\(id.description).txt")
        }
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: snapshotDirectoryURL,
            includingPropertiesForKeys: nil
        ) else { return }
        for url in contents where !retained.contains(url.lastPathComponent) {
            try? FileManager.default.removeItem(at: url)
        }
    }
```

- [ ] **Step 2: Verify it builds**

Run: `cd Apps/Conductor && swift build`
Expected: build succeeds.

- [ ] **Step 3: Commit**

```bash
git add Apps/Conductor/Sources/Conductor/Shared/WorkspacePersistence.swift
git commit -m "feat: store VT snapshots under .vt, keep .txt legacy read

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 9: Full build, smoke gate, and manual restore verification

**Files:** none (verification only)

- [ ] **Step 1: Run the unit tests**

Run: `cd Apps/Conductor && ./Scripts/swift-test.sh`
Expected: PASS — all `ConductorCoreTests` pass.

- [ ] **Step 2: Build and run the legacy smoke gate**

Run: `cd Apps/Conductor && swift build && swift run ConductorModelCheck`
Expected: `ConductorModelCheck passed`.

- [ ] **Step 3: Manual restore check**

1. Run: `cd Apps/Conductor && ./Scripts/run-conductor.sh` (or `./Scripts/build-app-bundle.sh && open .build/Conductor.app`).
2. In a terminal pane, produce **colored** output (e.g. `ls --color=always` or `git status` in a repo), some **CJK/emoji** text (e.g. `echo "中文 🚀 wide"`), and enough lines to exceed one screen.
3. Quit Conductor (Cmd-Q) so `flushPersistence` captures snapshots.
4. Relaunch.
5. Confirm the restored history: **keeps its colors**, has **no `�` (U+FFFD)** characters, shows **no `──── 上次会话 ────` marker lines**, and the CJK/emoji line is **not misaligned**.

Expected: all four hold. If color is missing, VT export silently fell back to plain text — check that `performBindingAction("write_screen_file:copy,vt")` returns true and that `NSPasteboard.general.string(forType:.string)` holds a temp-file path right after the call (add a temporary `ConductorLog` line in `capturedScrollbackVT` if needed, then remove it).

- [ ] **Step 4: Commit any fixes from Step 3**

If Step 3 required a fix, commit it with a descriptive message. Otherwise skip.

---

## Task 10: Migrate ConductorModelCheck assertions to Swift Testing (bulk, parallelizable)

This is a mechanical 1:1 port that locks the existing invariant coverage into `swift test`. It can be handed to a subagent. The `ConductorModelCheck` executable stays as-is (still the smoke gate).

**Files:**
- Create: `Apps/Conductor/Tests/ConductorCoreTests/WorkspaceModelTests.swift` (and, optionally, split by theme into `SearchTests.swift`, `WebTabTests.swift`, `RenderBudgetTests.swift`)

**Conversion rules (apply to every `check*` function in `Sources/ConductorModelCheck/main.swift`):**
1. `func checkSomething() { … }` → `@Test func something() { … }`.
2. `require(<cond>, "<msg>")` → `#expect(<cond>, "<msg>")`.
3. `return require(false, "<msg>")` (early-exit guards) → `Issue.record("<msg>"); return`.
4. Keep the test body otherwise identical — the same local variables, the same `WorkspaceState` calls.
5. Copy the helper `requireValidWorkspace` and the `SplitNode.usesOnly(axis:)` extension into the test file, renaming `require(...)` inside `requireValidWorkspace` to `#expect(...)`.
6. Do **not** port `func require` / `func requireValidWorkspace`'s `exit(1)` behavior — `#expect`/`Issue.record` already fail the test.
7. File header: `import Testing` + `@testable import ConductorCore`.

**Worked example A** — `checkNewWorkspace` becomes:

```swift
@Test func newWorkspaceStartsWithOnePane() {
    let workspace = WorkspaceState()
    #expect(workspace.root.leaves.count == 1, "new workspace should start with one pane")
    #expect(workspace.focusedPane?.tabs.count == 1, "new workspace should start with one terminal")
    #expect(workspace.focusedPane?.selectedTab?.title == "zsh", "initial terminal should be zsh")
    requireValidWorkspace(workspace, "new workspace")
}
```

**Worked example B** — an early-exit guard like `checkSplitRight`'s becomes:

```swift
@Test func splitRightAppendsPane() {
    var workspace = WorkspaceState()
    let originalPaneID = workspace.focusedPaneID
    guard let newPaneID = workspace.splitFocusedPane(.right, title: "agent") else {
        Issue.record("split right should be valid for a new workspace"); return
    }
    #expect(workspace.root.leaves == [originalPaneID, newPaneID], "split right should append a pane")
    #expect(workspace.focusedPaneID == newPaneID, "new split pane should be focused")
    // …remaining assertions converted the same way…
}
```

**Shared helper to include once in the test file:**

```swift
func requireValidWorkspace(_ workspace: WorkspaceState, _ context: String) {
    let leaves = workspace.root.leaves
    #expect(!leaves.isEmpty, "\(context): split tree should have at least one leaf")
    #expect(Set(leaves).count == leaves.count, "\(context): split tree should not duplicate panes")
    #expect(Set(leaves) == Set(workspace.panes.keys), "\(context): split leaves should match pane dictionary")
    #expect(workspace.panes[workspace.focusedPaneID] != nil, "\(context): focused pane should exist")
    for paneID in leaves {
        guard let pane = workspace.panes[paneID] else {
            Issue.record("\(context): leaf pane should exist"); return
        }
        #expect(!pane.tabs.isEmpty, "\(context): pane should always contain at least one tab")
        #expect(pane.tabs.contains(where: { $0.id == pane.selectedTabID }), "\(context): selected tab should exist in pane")
        #expect(Set(pane.tabs.map(\.id)).count == pane.tabs.count, "\(context): pane should not duplicate tabs")
    }
    if let zoomedPaneID = workspace.zoomedPaneID {
        #expect(workspace.panes[zoomedPaneID] != nil, "\(context): zoomed pane should exist")
    }
}

extension SplitNode {
    func usesOnly(axis expectedAxis: SplitAxis) -> Bool {
        switch self {
        case .leaf:
            return true
        case let .split(axis, first, second, _):
            return axis == expectedAxis && first.usesOnly(axis: expectedAxis) && second.usesOnly(axis: expectedAxis)
        }
    }
}
```

**Full list of `check*` functions to port** (from `Sources/ConductorModelCheck/main.swift`): `checkRenderBudgetDefaults`, `checkNewWorkspace`, `checkNewTerminalTab`, `checkSplitRight`, `checkSplitDownNested`, `checkWorkspaceEdgeSplitAvoidsCornerNesting`, `checkMixedPersistedLayoutNormalizes`, `checkSplitTreeReconciliationRestoresOrphanPanes`, `checkCloseSelectedTabFocusesNearestTab`, `checkCloseInactiveTabPreservesSelection`, `checkCloseOnlyTerminalCreatesReplacement`, `checkCloseLastTabInPaneCollapsesSplit`, `checkCloseNestedPaneCollapsesOnlyParent`, `checkCloseZoomedPaneClearsZoom`, `checkCloseDifferentPaneKeepsValidZoom`, `checkSplitLimit`, `checkAdjacentTabSelectionWraps`, `checkSplitFractionClamps`, `checkNestedSplitFractionClampsTargetPathOnly`, `checkEqualizeSplits`, `checkZoomUsesFocusedPaneAsVisibleRoot`, `checkFocusAdjacentPaneWraps`, `checkDirectionalPaneFocusPrefersSplitGeometry`, `checkResizeFocusedSplitChangesFraction`, `checkTerminalTitleUpdate`, `checkUserTerminalTitleIsStable`, `checkTerminalWorkingDirectoryUpdate`, `checkDuplicateTabCreatesFreshTerminalID`, `checkDuplicateWorkspaceCreatesFreshIDs`, `checkMoveSelectedTab`, `checkReorderTabBeforeTarget`, `checkMoveTabAcrossPanesByDrop`, `checkMoveOnlyTabByDropClosesSourcePane`, `checkInvalidDropDoesNotMutateWorkspace`, `checkMoveOnlyTabAcrossPanesClosesSourcePane`, `checkCommandAvailability`, `checkCloseOtherTabs`, `checkCloseTabsToRight`, `checkMoveSelectedTabToNextPane`, `checkMoveSelectedTabToNewSplit`, `checkMoveInactiveTabToNewSplitPreservesSourceSelection`, `checkMoveTabToNewSplitSupportsAllDropEdges`, `checkMoveTabToSplitAroundTargetPane`, `checkMoveOnlyTabToSplitAroundTargetPaneClosesSource`, `checkContextTabMoveAvailabilityUsesTargetTabPane`, `checkMoveTabToEndInSamePane`, `checkRapidTabSwitchingKeepsStableStructure`, `checkComplexWorkspaceStressMaintainsInvariants`, `checkAgentIntegrationCatalog`, `checkSearchMatcherRanking`, `checkSearchSelection`, `checkWebAddressResolver`, `checkWorkspaceWebTabList`.

- [ ] **Step 1: Port the functions** per the rules and examples above into `WorkspaceModelTests.swift` (optionally split the search/web/render-budget ones into themed files).

- [ ] **Step 2: Run the migrated tests**

Run: `cd Apps/Conductor && ./Scripts/swift-test.sh`
Expected: PASS — all migrated tests pass (count roughly matches the number of `check*` functions).

- [ ] **Step 3: Commit**

```bash
git add Apps/Conductor/Tests/ConductorCoreTests/
git commit -m "test: migrate ConductorModelCheck assertions to Swift Testing

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Self-Review Notes

- **Spec coverage:** §4 sanitizer → Tasks 2-4; §5.2 capture/replay → Tasks 6-7; §5.3 capture wiring → Task 7; §5.4 sidecar format → Task 8; §6 test net → Tasks 1 + 10; §7 error handling (fallback, pasteboard restore, temp-dir guard) → Tasks 5-7; §10 verification → Task 9. All covered.
- **Types are consistent across tasks:** `TerminalScrollbackSanitizer.{truncate,safeByteSuffix,normalizeLineEndings,wrapForReplay,prepareForReplay}`, `ExportedScreenPath.{normalized,isUnderTemporaryDirectory}`, `TerminalSurface.capturedScrollbackVT`.
- **Deferred (not in this plan, by spec §8):** Option A PTY replay, off-thread/line-bounded capture, SwiftUI divider, stash reconciliation.
