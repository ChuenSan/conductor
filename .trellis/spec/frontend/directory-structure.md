# Directory Structure

> How frontend code is organized in this project.

---

## Overview

The frontend is the native macOS product shell in `Apps/Conductor/Sources/Conductor`.
SwiftUI owns product composition and compact chrome. AppKit owns terminal host views,
responder-chain behavior, and Ghostty surface anchoring.

---

## Directory Layout

```
Apps/Conductor/Sources/Conductor/
├── App/
│   └── ConductorApp.swift
├── UI/
│   ├── ConductorRootView.swift
│   ├── ConductorWindowModel.swift
│   └── SplitNodeView.swift
├── Terminal/
│   ├── GhosttyAppRuntime.swift
│   ├── TerminalHostView.swift
│   ├── TerminalSurface.swift
│   └── TerminalSurfaceRepresentable.swift
└── Shared/
    ├── ConductorLog.swift
    └── TerminalTheme.swift
```

---

## Module Organization

UI files may observe `ConductorCore` models and own compact UI state such as selected
workspace, focused pane, visible sidebar, or theme. UI files must not own terminal
transcript, scrollback, cell grid, ANSI state, or raw output buffers.

Terminal host files are AppKit-adjacent. A SwiftUI representable may anchor a terminal
surface, but the expensive runtime owner belongs in `TerminalSurface`, not in a SwiftUI
view struct.

When split/tab behavior changes, update `ConductorCore` first and validate it with
`swift run ConductorModelCheck`.

---

## Naming Conventions

Use names that make the framework boundary obvious:

- `*View` for SwiftUI composition or AppKit view subclasses.
- `*Representable` only for SwiftUI-to-AppKit bridges.
- `*Model` for observable product state around the window.
- `*State` for value types in `ConductorCore`.

---

## Examples

- `Apps/Conductor/Sources/Conductor/UI/ConductorRootView.swift`
- `Apps/Conductor/Sources/Conductor/UI/SplitNodeView.swift`
- `Apps/Conductor/Sources/Conductor/Terminal/TerminalSurfaceRepresentable.swift`
