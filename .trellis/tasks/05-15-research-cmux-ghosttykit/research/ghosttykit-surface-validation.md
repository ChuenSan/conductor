# GhosttyKit Surface Validation Plan

## What Validation Means

Validation is a small, runnable spike that proves or disproves the current architecture route before building the full product. It is not the real app and not a polished UI. Its job is to answer: can we host GhosttyKit's terminal surface inside our SwiftUI/AppKit UI without long-output lag, focus/input bugs, or surface lifecycle instability?

## Route Under Test

```text
SwiftUI product shell
-> stable AppKit terminal host
-> GhosttyKit/libghostty macOS surface
-> Ghostty-owned terminal character rendering
```

This validation does not embed Ghostty.app. It also does not implement our own terminal cell renderer. The custom VT/render-state renderer path is deliberately out of scope for this first proof.

## Prototype Shape

Build the smallest macOS prototype that has:

- A SwiftUI shell with a sidebar row, toolbar/status label, and one terminal pane.
- An AppKit `NSViewRepresentable` or portal anchor that hosts a stable terminal AppKit view.
- A singleton Ghostty runtime initialized once.
- One terminal surface owner that creates a `ghostty_surface_t` only after its view has a real `NSWindow`.
- Keyboard, paste/text injection, mouse, scroll, focus, and resize routing into Ghostty surface APIs.
- A metadata path that updates only small snapshots such as title, running state, unread/notification count, and rough output counters.

## Required Proofs

- The project can acquire and link `GhosttyKit.xcframework`.
- The app launches and shows a working shell or configured command.
- Text input, paste, control keys, mouse selection, scrolling, and focus work.
- Resize updates display id, content scale, and pixel size without repeated redundant calls.
- Long output such as `yes | head -100000` or a fast loop does not push transcript text into SwiftUI state and does not make the sidebar/toolbar freeze.
- A simple split/tab stress test can swap or reparent the terminal host without destroying the surface. If this fails, the result should trigger the cmux-style portal path.
- Automation can send bulk text through `ghostty_surface_text` and control keys through `ghostty_surface_key`.
- Ghostty actions such as bell, notification, close, and split requests can be bridged into our product model as small events.

## Success Criteria

- One Ghostty app runtime, one surface owner per pane, no runtime recreation during ordinary SwiftUI updates.
- Long output remains visibly smooth enough for interactive work while product UI metadata stays responsive.
- SwiftUI stores no terminal transcript, scrollback, cells, or ANSI state.
- Surface lifecycle logs show creation only on real pane creation and free only on pane close/app teardown.
- Repeated resize/focus/layout cycles are deduplicated.
- Any black frame, lost focus, stale surface pointer, or teardown race is reproducible with logs and tied to a next architectural decision.

## Failure Criteria

- GhosttyKit cannot be acquired or linked reliably.
- The surface requires app-level embedding behavior that prevents our own UI hierarchy.
- Long output stalls the main thread even when SwiftUI receives only metadata.
- Reparenting/splits cannot be stabilized even with a portal.
- Required input, paste, automation, or notification hooks cannot be routed without owning the renderer.

If these failures occur, the next validation target is Ghostty's `libghostty-vt` APIs plus our own AppKit/Metal renderer.

## Measurements

- Add lifecycle logs for runtime init, surface create/free, focus, scale, display id, and size changes.
- Add signposts or timestamped logs around main-thread metadata updates.
- Track visible UI responsiveness during long output, workspace switching, split resizing, and paste bursts.
- Record rough memory and CPU observations from Activity Monitor or Instruments during stress runs.

## cmux References

- `/tmp/codex-cmux-reference/scripts/ensure-ghosttykit.sh`
- `/tmp/codex-cmux-reference/scripts/download-prebuilt-ghosttykit.sh`
- `/tmp/codex-cmux-reference/Sources/GhosttyTerminalView.swift`
- `/tmp/codex-cmux-reference/Sources/TerminalWindowPortal.swift`
- `/tmp/codex-cmux-reference/Sources/TerminalController.swift`

## Validation Run: 2026-05-15

Completed the first dependency validation:

- Used cmux's pinned Ghostty submodule SHA `aef980e27b584a9d914f1ff0499b13c6ed1973e0`.
- Downloaded the prebuilt release artifact through `/tmp/codex-cmux-reference/scripts/download-prebuilt-ghosttykit.sh`.
- The script verified the pinned SHA256 and extracted `GhosttyKit.xcframework` successfully.
- Extracted artifact path: `/tmp/codex-ghosttykit-validation/GhosttyKit.xcframework`.
- Extracted size: about `536M`.
- macOS slice includes `macos-arm64_x86_64/ghostty-internal.a`, `Headers/ghostty.h`, and `Headers/module.modulemap`.

Current environment blockers for the next runnable app validation:

- `zig` is not installed, so local GhosttyKit builds cannot run here yet.
- `xcodebuild` reports that the active developer directory is Command Line Tools, not full Xcode. A normal macOS app/Xcode project build needs full Xcode selected.
- Swift is available (`Apple Swift 6.3.1`), so source-level Swift checks are possible, but the next meaningful proof is still an actual macOS app spike that links GhosttyKit and hosts a surface.

## Validation Run: Prototype

Created a runnable SwiftPM prototype at `/Users/uchihasasuke/Desktop/conductor/Prototypes/GhosttySurfaceValidation`.

What it proves:

- SwiftPM can build a minimal SwiftUI/AppKit app that links the cmux-pinned `GhosttyKit.xcframework`.
- The cmux prebuilt archive needs a SwiftPM normalization step because the macOS static library is named `ghostty-internal.a`; the prototype prepare script renames it to `libghostty-internal.a` and updates `Info.plist` inside the ignored local `Vendor/GhosttyKit.xcframework`.
- The app creates a custom SwiftUI shell, a stable AppKit terminal host view, and a Ghostty macOS surface after the view has a real window.
- The terminal opens as a normal shell and renders real Ghostty output in the AppKit host.
- The toolbar stress button can send a long-output command and Ghostty renders the resulting stream without transcript text entering SwiftUI state.
- Input ownership was corrected during validation: the host should not implement terminal line-editing behavior. It should forward ordinary keyboard, modifier, mouse, scroll, and paste-related events into Ghostty surface APIs, while app commands remain outside terminal input.
- The validation app can change both product UI colors and Ghostty terminal colors. The SwiftUI shell changes compact theme state; the live Ghostty surface receives a config string containing `palette`, `background`, `foreground`, cursor, and selection colors via `ghostty_surface_update_config`.

Important implementation lesson:

- `ghostty_surface_text` is appropriate for automation/bulk text and paste-like delivery.
- Control keys, Enter, modifier transitions, and normal keyboard behavior should use `ghostty_surface_key` with macOS key codes and modifier flags.
- App shortcuts used for product commands must be consumed before they reach the terminal. Prototype stress is therefore a toolbar command rather than a terminal keyboard shortcut.
- Terminal theme changes should remain config updates, not terminal transcript/state updates. Do not use SwiftUI to recolor individual terminal cells.

Verification commands:

```bash
cd /Users/uchihasasuke/Desktop/conductor/Prototypes/GhosttySurfaceValidation
./Scripts/prepare-ghosttykit.sh
swift build
swift run GhosttySurfaceValidation
```

Observed build status:

- `swift build` passes.
- The linker emits warnings about ImGui symbols from the bundled Ghostty static library, but the executable links and runs.

## Validation Run: Full Matrix

Extended the prototype into a small multi-pane matrix and ran the route against the product behaviors we care about first:

- Multiple Ghostty surfaces can be created from the same app runtime. The matrix run created three panes and each pane owned an independent `ghostty_surface_t`.
- Split layout can switch between column and row arrangements without recreating the Ghostty runtime.
- Pane ordering can be swapped from SwiftUI state while the terminal hosts remain AppKit-backed surface owners.
- Theme updates can be applied across all live surfaces. The run switched to the Poimandres palette and all panes received the Ghostty config update.
- `Stress All` sent long-output commands to every pane. All three panes streamed `validation-output-line` concurrently through Ghostty rendering.
- The SwiftUI state stayed compact: pane list, selected theme, split axis, and command count. Terminal transcript, scrollback, cell grid, and ANSI state are not stored in SwiftUI.
- The app still opens normal shells; stress commands are toolbar-driven validation automation, not replacement terminal behavior.

Automated checks after the matrix work:

```bash
cd /Users/uchihasasuke/Desktop/conductor/Prototypes/GhosttySurfaceValidation
swift build

cd /Users/uchihasasuke/Desktop/conductor
python3 .trellis/scripts/task.py validate 05-15-research-cmux-ghosttykit
```

Both checks passed on 2026-05-15.

Follow-up work closed the largest gaps in the first matrix:

- The host view now participates in `NSTextInputClient` and routes `interpretKeyEvents` output into Ghostty key/text APIs.
- Marked/preedit text is forwarded with `ghostty_surface_preedit`.
- IME candidate positioning uses `ghostty_surface_ime_point`.
- Command-modified key equivalents can ask Ghostty whether an event is a terminal binding before app/menu handling.

## Validation Run: Automated Full Pass

Added `GHOSTTY_VALIDATION_AUTORUN=1` to make the validation reproducible without relying on AppleScript focus. The app now starts, creates three panes, changes layout, swaps panes, switches to Poimandres, sends validation commands through the terminal surfaces, stresses all panes, and exits.

Command:

```bash
cd /Users/uchihasasuke/Desktop/conductor/Prototypes/GhosttySurfaceValidation
GHOSTTY_VALIDATION_AUTORUN=1 swift run GhosttySurfaceValidation
```

Observed outputs on 2026-05-15:

- `/tmp/ghostty-pane-1-validation.txt` -> `pane-1-ok`
- `/tmp/ghostty-pane-2-validation.txt` -> `pane-2-ok`
- `/tmp/ghostty-pane-3-validation.txt` -> `pane-3-ok`
- `/tmp/ghostty-paste-validation.txt` -> `中文-paste-ok`
- `/tmp/ghostty-ctrl-validation.txt` -> `ctrl-body-ok`
- `/tmp/ghostty-ime-validation.txt` -> `中文-ime-ok`

This validates:

- Three independent Ghostty surfaces under one runtime.
- SwiftUI split/layout/theme state changes around live surfaces.
- Long-output stress while transcript remains outside SwiftUI state.
- Typed text delivered as Ghostty key events.
- Bulk/paste/automation text delivered through Ghostty text APIs.
- Ctrl-D delivered as a control-key event.
- Chinese committed text through the AppKit text-input path.
- Preedit forwarding to Ghostty without replacing shell behavior in Swift.

Performance sampling:

```bash
sample <GhosttySurfaceValidation-pid> 5 -file /tmp/ghostty-sample.txt
```

During the sampled stress run, the main thread was primarily parked in AppKit/CoreFoundation event-loop waiting, not busy diffing transcript text. Physical footprint was about `316M`, peak about `321M`, with three surfaces active and stress output running.

Production QA still needs a human pass for the visible IME candidate UI and every configured keyboard layout, but the architecture-level routes are now validated by executable checks. Portal-style hosting is not required for this prototype; it remains the fallback if production split/tab churn causes black frames, stale focus, or surface teardown races.
