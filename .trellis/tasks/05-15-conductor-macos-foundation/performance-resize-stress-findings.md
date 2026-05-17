# Resize Stress Performance Findings

Date: 2026-05-17

## Scenario

The automated resize stress route runs Conductor with:

- 3 visible panes.
- 4 terminal tabs / Ghostty surfaces.
- large terminal output sent through each visible pane.
- 32 low-interval split resize operations, with pane focus changes and equalize operations interleaved.

The route is invoked by `CONDUCTOR_RESIZE_STRESS_AUTORUN=1` and is part of
`Apps/Conductor/Scripts/check-conductor.sh`.

Expected output:

```text
status=ok
stress=resize-while-output
resized=true
panes=3
terminals=4
surfaces=4
zoomed=false
```

## Result

The route passes in the full local gate. The stress route also disables workspace
persistence through `WorkspacePersistence.isEnabledByDefault`, matching the other
automation paths, so it does not mutate the user's real window state.

## Sampling Evidence

`xcrun xctrace` is not available in the current environment:

```text
xcrun: error: unable to find utility "xctrace", not a developer tool or in PATH
```

As a fallback, `/usr/bin/sample` was run against the live resize stress process:

```bash
CONDUCTOR_RESIZE_STRESS_AUTORUN=1 \
CONDUCTOR_RESIZE_STRESS_OUTPUT=/tmp/conductor-resize-profile-ok.txt \
.build/debug/Conductor &
sample "$pid" 3 -file /tmp/conductor-resize-sample.txt
```

Observed summary:

- Sample interval: 1 ms for 3 seconds.
- Physical footprint: ~419 MB, peak ~438 MB.
- Main thread was largely in AppKit event/display-cycle work.
- The most visible main-thread stack was AppKit/SwiftUI cursor and tracking-area update work during resize/display cycles.
- No sampled stack showed terminal transcript text, scrollback, ANSI cell rendering, or raw output flowing through SwiftUI state.
- Ghostty renderer / io / io-reader threads remained separate from SwiftUI shell work.

## Interpretation

The current evidence supports the architecture boundary: terminal output remains in
Ghostty/AppKit surfaces while SwiftUI handles compact shell metadata and layout chrome.
The active resize pressure visible in sampling is AppKit/SwiftUI structural and cursor
tracking work, not transcript rendering in SwiftUI.

## Remaining Verification

This is not a replacement for a full Instruments trace. Before release, run the same
route with Xcode Instruments / Time Profiler and SwiftUI tooling when `xctrace` or
the Instruments app is available. Focus on:

- main-thread time in SwiftUI `ViewGraph` updates during split resize.
- cursor/tracking-area churn around split dividers.
- Ghostty surface resize signposts.
- whether metadata publish remains bounded while long output is active.
