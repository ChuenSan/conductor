# Terminal Background Image And Blur Settings

## Goal

Add complete terminal background controls to the existing terminal appearance settings: blur strength, background image import/clear, image opacity, fit mode, position, and repeat mode.

## Requirements

- Keep Ghostty/libghostty as the terminal character renderer.
- Do not move terminal text, scrollback, or per-cell rendering into SwiftUI.
- Persist background controls through terminal appearance overrides and profile JSON.
- Emit corresponding Ghostty config keys:
  - `background-opacity`
  - `background-opacity-cells`
  - `background-blur`
  - `background-image`
  - `background-image-opacity`
  - `background-image-fit`
  - `background-image-position`
  - `background-image-repeat`
- Keep AppKit host and SwiftUI terminal container backgrounds aligned with resolved terminal background opacity.
- Add settings UI in the terminal appearance section with compact controls.
- Allow selecting local image files via `NSOpenPanel`.
- Allow clearing the selected background image and resetting advanced background controls.

## Validation

- `swift build`
- `swift run ConductorModelCheck`
- `git diff --check`
- Rebuild and restart the local `.app`.
