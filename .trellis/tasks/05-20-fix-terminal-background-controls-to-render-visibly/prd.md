# Fix Terminal Background Controls To Render Visibly

## Goal

Make terminal background controls visibly work in the app instead of relying only on Ghostty config keys that may not hot-update through the embedded macOS surface.

## Requirements

- Keep Ghostty as the terminal character renderer.
- Do not render terminal text or scrollback in SwiftUI.
- Render background image, fit, position, repeat, opacity, and blur through a stable AppKit background layer behind the Ghostty host view.
- Keep Ghostty config emission for compatibility, but make the app-owned layer the visible source of truth.
- Keep terminal geometry/focus behavior stable.

## Validation

- `swift build`
- `swift run ConductorModelCheck`
- `git diff --check`
- Rebuild and restart the local app.
