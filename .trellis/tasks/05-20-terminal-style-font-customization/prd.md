# research: terminal style and font customization

## Goal

Design full terminal appearance customization for Conductor, including styles, fonts, presets,
scope overrides, import/export, and GhosttyKit integration while preserving the current
high-performance terminal architecture.

## What I already know

* The requested feature is terminal visual customization, specifically terminal style/theme and terminal font changes.
* The app uses GhosttyKit/libghostty for the live terminal renderer.
* The app already has SwiftUI shell themes and appearance preferences.
* Terminal theme color palettes and terminal font size are already wired to Ghostty config updates.
* Terminal font family is feasible but needs a new terminal-specific preference, separate from the shell UI font family.
* The product direction is a complete design, not an MVP-only global setting.

## Assumptions (temporary)

* The implementation should keep terminal scrollback, transcript text, ANSI rendering, cursor movement, and high-frequency output out of SwiftUI state.
* User-facing controls should live in the existing settings surface, then flow down to the AppKit/GhosttyKit host.
* Appearance should resolve from global defaults through workspace and terminal overrides.

## Open Questions

* Which implementation slice should land first after the full design is accepted?

## Requirements (evolving)

* Determine whether terminal font family and size can be configured.
* Determine whether terminal color palette/theme can be configured.
* Identify the likely implementation entry points and risks.
* Preserve GhosttyKit/libghostty ownership of the live character renderer.
* Support global, workspace, and terminal-level appearance scopes.
* Support user-editable terminal appearance profiles.
* Support terminal font family, fallback chain, size, and conservative advanced font tuning.
* Support terminal color palette, foreground/background, cursor, and selection customization.
* Support import/export for Ghostty-compatible theme fragments and Conductor full-fidelity profiles.

## Acceptance Criteria (evolving)

* [x] Feasibility conclusion for terminal font changes.
* [x] Feasibility conclusion for terminal color/style changes.
* [x] Recommended implementation path with affected files.
* [x] Known risks and validation steps documented.
* [x] Full product and technical design documented.
* [x] Core appearance model, inheritance resolver, and Ghostty config text builder drafted.
* [x] Workspace and terminal override persistence fields drafted.
* [ ] Full settings UI and live per-scope runtime update path implemented.

## Definition of Done (team quality bar)

* Tests added/updated when implementation begins.
* Lint / typecheck / CI green when implementation begins.
* Docs/notes updated if behavior changes.
* Rollout/rollback considered if risky.

## Deferred From Current Slice

* Replacing GhosttyKit/libghostty rendering with a SwiftUI per-cell renderer.
* Importing arbitrary non-Ghostty terminal theme formats unless selected for a later implementation task.
* Full settings UI, profile import/export, and per-scope live update routing.

## Technical Notes

* Detailed research: `research/terminal-style-font-feasibility.md`.
* Full design: `info.md`.
* Relevant code:
  * `Apps/Conductor/Sources/Conductor/Shared/AppearancePreferences.swift`
  * `Apps/Conductor/Sources/Conductor/Shared/TerminalTheme.swift`
  * `Apps/Conductor/Sources/Conductor/Terminal/GhosttyAppRuntime.swift`
  * `Apps/Conductor/Sources/Conductor/Terminal/TerminalSurface.swift`
  * `Apps/Conductor/Sources/Conductor/UI/ConductorWindowModel.swift`
  * `Apps/Conductor/Sources/Conductor/UI/ConductorRootView.swift`
