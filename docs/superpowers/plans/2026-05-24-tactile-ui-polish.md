# Tactile UI Polish Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Improve high-frequency UI feel by tightening shell edges, reducing oversized generated-looking settings surfaces, and making Command Center more compact.

**Architecture:** Keep this as a focused SwiftUI polish pass. Touch only shell/sidebar, settings shortcut guide, and command/search overlay presentation; do not add product features or restructure app state.

**Tech Stack:** SwiftUI, AppKit-backed macOS app, existing Conductor theme tokens, `ConductorMotion`, SwiftPM checks.

---

### Task 1: Sidebar Corner And Dock Polish

**Files:**
- Modify: `Apps/Conductor/Sources/Conductor/UI/Sidebar/ConductorSidebar.swift`

- [ ] **Step 1: Write the failing source check**

```bash
swift - <<'SWIFT'
import Foundation
let source = try String(contentsOfFile: "Apps/Conductor/Sources/Conductor/UI/Sidebar/ConductorSidebar.swift", encoding: .utf8)
func require(_ condition: Bool, _ message: String) {
    if !condition {
        FileHandle.standardError.write(("FAIL: " + message + "\n").data(using: .utf8)!)
        exit(1)
    }
}
require(source.contains("SidebarDockSurface("), "Expanded sidebar dock should use a resolved dock surface")
require(source.contains("collapsedSidebarFooterSurface"), "Collapsed sidebar footer should use a flush footer surface")
require(source.contains("bottomTrailingRadius: CGFloat = ConductorDesign.sidebarCornerRadius"), "Sidebar rail bottom radii should resolve consistently")
print("sidebar polish source check passed")
SWIFT
```

- [ ] **Step 2: Run check to verify it fails**

Run the command from Step 1. Expected: `FAIL: Expanded sidebar dock should use a resolved dock surface`.

- [ ] **Step 3: Implement sidebar polish**

Add a small `SidebarDockSurface` helper, wrap the expanded dock controls in it, wrap collapsed footer in a flush footer surface, and set `SidebarRailShape.bottomTrailingRadius` to `ConductorDesign.sidebarCornerRadius`.

- [ ] **Step 4: Verify**

Run Step 1 source check, then:

```bash
swift build --package-path Apps/Conductor --product Conductor
```

Expected: build exits 0.

- [ ] **Step 5: Commit**

```bash
git add Apps/Conductor/Sources/Conductor/UI/Sidebar/ConductorSidebar.swift
git commit -m "polish: resolve sidebar dock edges"
```

### Task 2: Flatten Shortcuts Settings

**Files:**
- Modify: `Apps/Conductor/Sources/Conductor/UI/Settings/SettingsSections.swift`
- Modify: `Apps/Conductor/Sources/Conductor/UI/Settings/SettingsControls.swift`

- [ ] **Step 1: Write the failing source check**

```bash
swift - <<'SWIFT'
import Foundation
let sections = try String(contentsOfFile: "Apps/Conductor/Sources/Conductor/UI/Settings/SettingsSections.swift", encoding: .utf8)
let controls = try String(contentsOfFile: "Apps/Conductor/Sources/Conductor/UI/Settings/SettingsControls.swift", encoding: .utf8)
func require(_ condition: Bool, _ message: String) {
    if !condition {
        FileHandle.standardError.write(("FAIL: " + message + "\n").data(using: .utf8)!)
        exit(1)
    }
}
require(sections.contains("CommandShortcutGuide(rows: commandShortcutRows(), height: 320, style: .plain)"), "Shortcut page should use taller plain guide")
require(controls.contains("enum CommandShortcutGuideStyle"), "Shortcut guide should expose plain/card styles")
require(controls.contains("case plain"), "Shortcut guide should have plain style")
require(controls.contains("CommandShortcutSectionDivider"), "Shortcut guide should use low-weight section dividers")
print("shortcut settings source check passed")
SWIFT
```

- [ ] **Step 2: Run check to verify it fails**

Expected: `FAIL: Shortcut page should use taller plain guide`.

- [ ] **Step 3: Implement shortcut page polish**

Add `CommandShortcutGuideStyle`, make existing card treatment available as `.card`, use `.plain` in command settings, reduce heavy card background, use thinner section dividers, and make shortcut chips less pill-heavy.

- [ ] **Step 4: Verify**

Run Step 1 source check, then:

```bash
swift build --package-path Apps/Conductor --product Conductor
```

Expected: build exits 0.

- [ ] **Step 5: Commit**

```bash
git add Apps/Conductor/Sources/Conductor/UI/Settings/SettingsSections.swift Apps/Conductor/Sources/Conductor/UI/Settings/SettingsControls.swift
git commit -m "polish: flatten shortcuts settings"
```

### Task 3: Compact Command Center

**Files:**
- Modify: `Apps/Conductor/Sources/Conductor/UI/Shell/ShellRootView.swift`

- [ ] **Step 1: Write the failing source check**

```bash
swift - <<'SWIFT'
import Foundation
let source = try String(contentsOfFile: "Apps/Conductor/Sources/Conductor/UI/Shell/ShellRootView.swift", encoding: .utf8)
func require(_ condition: Bool, _ message: String) {
    if !condition {
        FileHandle.standardError.write(("FAIL: " + message + "\n").data(using: .utf8)!)
        exit(1)
    }
}
require(source.contains("CommandPaletteHeader("), "Command Center should use compact header")
require(source.contains(".frame(width: 660, height: 430)"), "Command Center should be more compact")
require(source.contains("CommandSectionTitle(row.command.section, compact: true)"), "Command sections should render compactly")
print("command center polish source check passed")
SWIFT
```

- [ ] **Step 2: Run check to verify it fails**

Expected: `FAIL: Command Center should use compact header`.

- [ ] **Step 3: Implement compact command palette**

Replace the generic floating header with a compact header, reduce the panel frame, tighten internal spacing, and keep keyboard/search behavior unchanged.

- [ ] **Step 4: Verify**

Run Step 1 source check, then:

```bash
swift build --package-path Apps/Conductor --product Conductor
```

Expected: build exits 0.

- [ ] **Step 5: Commit**

```bash
git add Apps/Conductor/Sources/Conductor/UI/Shell/ShellRootView.swift
git commit -m "polish: compact command center"
```

### Task 4: Final Verification And Visual Check

**Files:**
- No code changes expected.

- [ ] **Step 1: Run model checks**

```bash
swift run --package-path Apps/Conductor ConductorModelCheck
```

Expected: `ConductorModelCheck passed`.

- [ ] **Step 2: Run full build**

```bash
swift build --package-path Apps/Conductor --product Conductor
```

Expected: build exits 0.

- [ ] **Step 3: Restart app**

```bash
pgrep -fl '/Conductor.app/Contents/MacOS/Conductor' || true
Apps/Conductor/Scripts/run-conductor.sh
```

Kill the previous Conductor process before running the script.

- [ ] **Step 4: Manual visual check**

Use Computer Use to inspect:

- Sidebar bottom-left settings corner.
- Command Center size and row density.
- Settings > Commands/Shortcuts surface.
- Terminal search followed by File Manager.

Expected: no overlay collision, no oversized shortcut card, no unresolved sidebar corner.
