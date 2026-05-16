# Directory Structure

> How runtime/platform code should be organized in this project.

---

## Overview

The formal macOS app lives under `Apps/Conductor`. Validation spikes stay under
`Prototypes/` and must not become production source dependencies.

---

## Directory Layout

```text
Apps/Conductor/
├── Package.swift
├── Scripts/
│   └── prepare-ghosttykit.sh
├── Sources/
│   ├── ConductorCore/
│   │   ├── Shared/
│   │   └── Workspace/
│   ├── Conductor/
│   │   ├── App/
│   │   ├── UI/
│   │   ├── Terminal/
│   │   └── Shared/
│   └── ConductorModelCheck/
└── Vendor/
    └── GhosttyKit.xcframework/  # prepared locally, ignored by Git
```

---

## Module Organization

Keep high-frequency runtime code out of SwiftUI feature directories. Terminal runtime, portal binding, resize/focus routing, PTY input, and Ghostty callbacks belong under `Sources/Conductor/Terminal/`.

Keep testable product models in `Sources/ConductorCore/`. Workspace split trees, pane IDs, terminal tab IDs, and future command routing contracts should be representable without importing SwiftUI, AppKit, or GhosttyKit.

Automation commands should call stable service APIs. They should not reach into SwiftUI views.

Browser/tool panes should be peers of terminal panes, not children of terminal rendering code.

Local dependency and validation artifacts are not production source:

- `Vendor/GhosttyKit.xcframework/` is prepared by script and ignored.
- `Backups/` is a local evidence archive and ignored.
- `Prototypes/` can be referenced for learning, but formal code must not import or depend on it.

---

## Naming Conventions

Use names that express ownership:

- `*View` for SwiftUI views or AppKit views, with the framework clear from context.
- `*Representable` for SwiftUI bridges into AppKit.
- `*Runtime` for long-lived Ghostty or process lifecycle owners.
- `*Pipeline` for background parsing/coalescing/snapshot production.
- `*Snapshot` or `*DisplayModel` for compact immutable UI metadata.
- `*Check` executable targets for environments where XCTest is unavailable but model assertions still need to run.

---

## Examples

Reference implementation to study: `/tmp/codex-cmux-reference`.

Useful cmux files:

- `Sources/GhosttyTerminalView.swift` for Ghostty app/surface lifecycle.
- `Sources/TerminalWindowPortal.swift` for the portal pattern that keeps terminal views stable outside SwiftUI churn.
- `Sources/Panels/TerminalPanel.swift` for separating panel metadata from runtime surface ownership.

Local production examples:

- `Apps/Conductor/Sources/ConductorCore/Workspace/WorkspaceModel.swift`
- `Apps/Conductor/Sources/Conductor/Terminal/GhosttyAppRuntime.swift`
- `Apps/Conductor/Sources/Conductor/Terminal/TerminalSurface.swift`
