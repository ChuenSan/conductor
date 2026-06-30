# Shortcut Recorder Settings Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the simple settings shortcut text fields with an Orca-style shortcut recorder, filters, conflict warnings, reset, and disable controls.

**Architecture:** Keep the existing `AppConfig.keybindings: [String: String]` storage model for this pass, so each command has at most one active shortcut. Add small pure presentation/editing helpers for normalization, row state, filters, and conflicts, then wire SwiftUI settings rows to a focused AppKit-backed recorder button that captures real key events.

**Tech Stack:** Swift, SwiftUI, AppKit `NSViewRepresentable`, XCTest, existing `KeyChord`, `AppCommand`, `ConfigStore`, and `CommandRegistry`.

---

### Task 1: Shortcut Editing Model

**Files:**
- Create: `Sources/ConductorApp/UI/ShortcutSettingsModel.swift`
- Test: `Tests/ConductorAppTests/ShortcutSettingsModelTests.swift`

- [ ] **Step 1: Write failing tests**

```swift
func testRowsExposeModifiedDisabledAndConflictState()
func testFilterCountsIncludeModifiedUnassignedAndConflicts()
func testCaptureRejectsConflictingShortcut()
func testResetRemovesOverrideAndDisableWritesEmptyOverride()
```

- [ ] **Step 2: Run model tests to verify failure**

Run: `swift test --filter ShortcutSettingsModelTests`
Expected: compile failure because `ShortcutSettingsModel` does not exist.

- [ ] **Step 3: Implement model helpers**

Add `ShortcutSettingsRow`, `ShortcutSettingsFilter`, and `ShortcutSettingsModel` helpers that compute effective bindings, modified/disabled state, search/filter results, conflicts, reset updates, disable updates, and capture updates.

- [ ] **Step 4: Run model tests**

Run: `swift test --filter ShortcutSettingsModelTests`
Expected: pass.

### Task 2: Key Event Capture

**Files:**
- Create: `Sources/ConductorApp/UI/ShortcutRecorderControl.swift`
- Test: `Tests/ConductorAppTests/ShortcutRecorderControlTests.swift`

- [ ] **Step 1: Write failing tests**

```swift
func testCaptureDisplayUsesSymbolizedShortcut()
func testRecordingPromptAndAccessibilityLabel()
func testEventCaptureNormalizesCommandShiftD()
```

- [ ] **Step 2: Run tests to verify failure**

Run: `swift test --filter ShortcutRecorderControlTests`
Expected: compile failure because recorder presentation helpers do not exist.

- [ ] **Step 3: Implement recorder control**

Add `ShortcutRecorderPresentation` plus an `NSViewRepresentable` wrapping an `NSButton` subclass. The button enters recording on click, captures `NSEvent.keyDown`, cancels on Escape, ignores modifier-only presses, emits normalized `cmd+shift+d` style strings, and exposes labels/tooltips.

- [ ] **Step 4: Run recorder tests**

Run: `swift test --filter ShortcutRecorderControlTests`
Expected: pass.

### Task 3: Settings UI Replacement

**Files:**
- Modify: `Sources/ConductorApp/UI/SettingsView.swift`
- Test: `Tests/ConductorAppTests/SettingsShortcutPresentationTests.swift`

- [ ] **Step 1: Write failing presentation tests**

```swift
func testShortcutSectionShowsFilterCounts()
func testShortcutRowsAreGroupedByCommandScope()
func testSearchMatchesCommandTitleIDAndShortcut()
```

- [ ] **Step 2: Run tests to verify failure**

Run: `swift test --filter SettingsShortcutPresentationTests`
Expected: compile or assertion failure for missing presentation helpers.

- [ ] **Step 3: Replace text fields**

Remove keybinding draft text fields from the shortcut section. Add a search field, status filter segmented control, grouped command rows, shortcut recorder capsule, reset button, disable button, and inline conflict/helper messages.

- [ ] **Step 4: Run focused tests**

Run: `swift test --filter 'ShortcutSettingsModelTests|ShortcutRecorderControlTests|SettingsShortcutPresentationTests'`
Expected: pass.

### Task 4: Verification

**Files:**
- No new files.

- [ ] **Step 1: Run full tests**

Run: `swift test`
Expected: all tests pass.

- [ ] **Step 2: Run format check**

Run: `git diff --check`
Expected: no output.

- [ ] **Step 3: Launch app**

Run: `./script/build_and_run.sh --verify && sleep 4 && pgrep -x ConductorApp`
Expected: command exits 0 and prints the running app PID.
