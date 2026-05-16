# Ghostty Surface Validation

Minimal runnable spike for the current terminal route:

```text
SwiftUI product shell
-> stable AppKit terminal host
-> GhosttyKit/libghostty macOS surface
-> Ghostty-owned terminal character rendering
```

This prototype is intentionally small. It validates dependency acquisition, Ghostty runtime initialization, surface creation after the host view has a window, size/scale/display synchronization, simple text injection, paste, scroll, focus, and long-output stress entry points.

## Prepare

```bash
./Scripts/prepare-ghosttykit.sh
```

The script downloads the cmux-pinned `GhosttyKit.xcframework` into `Vendor/`, verifies the pinned SHA256, and leaves the binary ignored by git.

## Build

```bash
swift build
```

## Run

```bash
swift run GhosttySurfaceValidation
```

The window starts a normal shell. Use the toolbar buttons to send long-output stress commands, add/close panes, switch split layout, swap panes, or manually refresh Ghostty surfaces. Use the sidebar theme choices to change both the SwiftUI shell colors and the Ghostty terminal palette.

## Automated Validation

```bash
GHOSTTY_VALIDATION_AUTORUN=1 swift run GhosttySurfaceValidation
```

This creates three panes, changes layout/theme, sends typed text, automation text, Ctrl-D, and AppKit text-input committed Chinese text through Ghostty, runs stress output, then exits. It writes validation files under `/tmp/ghostty-*-validation.txt`.

## Current Environment Note

This package can be type-checked with SwiftPM, but a complete app-style build may still require full Xcode on machines where `xcodebuild` points only at Command Line Tools.
