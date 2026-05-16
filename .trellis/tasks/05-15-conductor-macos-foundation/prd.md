# Build Conductor macOS Foundation

## Goal

Create the first production-grade macOS app foundation for Conductor, separate from the verified Ghostty validation prototype. The app should establish clean module boundaries, stable terminal ownership, and a Codex-inspired native UI shell that lets users work directly inside Ghostty-backed terminal panes.

## Product Direction

Conductor is a native macOS multi-terminal manager. It should feel like a focused developer workspace, not a chat surface. Terminals are directly interactive and should occupy nearly all of the working canvas.

The initial foundation must support:

- One app window with a compact sidebar and dense top toolbar.
- A workspace model containing panes, pane tabs, and terminal surfaces.
- Actions named in product language: `New Terminal`, `Split Right`, `Split Down`, `New Tab`.
- A split layout that can show multiple terminal panes in one window.
- Real GhosttyKit/libghostty terminal surfaces hosted in stable AppKit views.
- No bottom composer, no top command input, and no transcript text rendered through SwiftUI.

## Architecture Requirements

- Do not reuse the validation prototype as the formal app source tree.
- Use the validation prototype and cmux only as references for integration behavior.
- Create a clean production source layout under `Apps/Conductor`.
- Keep terminal runtime code out of SwiftUI view files.
- Initialize one Ghostty app runtime and create one surface owner per terminal tab/surface.
- Create Ghostty surfaces only after the AppKit host view has a real `NSWindow`.
- Keep AppKit terminal host identity stable across SwiftUI updates.
- Deduplicate resize, focus, scale, and display-id updates.
- Route keyboard, text input, IME, paste, mouse, and scroll events through Ghostty surface APIs.
- Preserve a future route to a cmux-style portal if SwiftUI reparenting causes surface churn.

## Performance Requirements

- SwiftUI state may contain workspace structure, focused IDs, theme selection, and compact metadata.
- SwiftUI state must not contain terminal transcript, scrollback, ANSI state, cell grids, or raw output buffers.
- High-frequency terminal callbacks must be coalesced before they update app chrome.
- Long output should not make sidebar, toolbar, tabs, or split chrome slower as transcript length grows.

## First Implementation Scope

- Add the formal app package under `Apps/Conductor`.
- Add a production-oriented GhosttyKit preparation script for the formal app.
- Add app shell, workspace/split model, terminal surface owner, AppKit host view, input router, theme tokens, and logging.
- Make the app compile with SwiftPM.
- Make the app runnable after preparing GhosttyKit.
- Include lightweight tests for workspace split/tab behavior where practical.

## Out of Scope For This Task

- Full notification center.
- Agent orchestration.
- Browser/tool panes.
- Persistent workspace restore.
- Full cmux portal implementation unless the initial stable host proves inadequate.
- Custom terminal cell renderer.

## Acceptance Criteria

- The verified prototype is backed up separately from formal app code.
- `Apps/Conductor` is a clean source tree and does not depend on files inside `Prototypes/GhosttySurfaceValidation`.
- The formal app builds with `swift build`.
- The formal app can launch a directly usable Ghostty-backed terminal surface after `Scripts/prepare-ghosttykit.sh`.
- The UI has no chat composer or command input strip.
- A workspace can model multiple terminal panes/tabs and expose `New Terminal`, `Split Right`, `Split Down`, and `New Tab` actions.
- Tests or build-time checks cover the workspace layout model.

## Hardening Roadmap

The foundation is not considered good enough when it merely compiles. It should become
stable, quick to operate, and predictable under real terminal workflows.

### Phase A: Pane / Tab Basics

- Tab switching in the same pane must swap the visible terminal surface immediately.
- Tab clicks must not create unnecessary Ghostty surfaces or rebuild unrelated panes.
- Every tab must have a close affordance and a keyboard command.
- Closing a selected tab should focus the nearest surviving tab.
- Closing the last tab in a pane should close the pane when another pane exists.
- Closing the only remaining terminal in the workspace should create a replacement shell
  instead of leaving a blank workspace.
- New Terminal should mean a browser-style new terminal tab in the focused pane.
- Split Right and Split Down should create a new pane with a new terminal and focus it.

### Phase B: Production Split Layout

- Split dividers must be draggable.
- Split fractions must be stored in the model and clamped to usable pane sizes.
- Pane close should collapse the split tree cleanly.
- Pane focus should work by click, keyboard, and Ghostty split actions.
- Equalize splits and toggle zoom should be modeled before advanced UI polish.

### Phase C: Ghostty Action Bridge

- Study cmux action handling before implementing each Ghostty action.
- Map Ghostty new split actions into our split model.
- Map Ghostty focus split actions into our focus model.
- Map Ghostty resize/equalize/zoom actions into our layout model.
- Keep Ghostty keybindings working while app-level shortcuts remain explicit.

### Phase D: Interaction Quality

- Add close, move, and reorder for terminal tabs.
- Add move tab to new pane and move pane to new window later.
- Add focus shortcuts for next/previous tab and adjacent panes.
- Add command palette entries for all pane/tab operations.
- Ensure controls are reachable without stealing focus unexpectedly from the terminal.

### Phase E: Performance / Stability

- Measure tab switching, split creation, and split resize under active terminal output.
- Keep transcript and scrollback out of SwiftUI state.
- Avoid whole-window invalidation when one pane changes focus or tab selection.
- Keep terminal host views stable until a real close operation.
- Add lifecycle logs for create, attach, focus, resize, tab close, pane close, and free.
- Revisit cmux-style portal hosting if SwiftUI reparenting causes black frames or focus loss.

### Phase F: Regression Checks

- Extend `ConductorModelCheck` for tab close, pane close, nested split collapse, focus
  movement, and action-bridge commands.
- Add a UI smoke script that starts Conductor, creates tabs/splits, switches tabs, and
  closes them without leaving stale processes.
