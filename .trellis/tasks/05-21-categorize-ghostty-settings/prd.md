# Categorize Ghostty Settings By Function

## Goal

Replace the raw 194-key Ghostty settings list with a productized settings surface. Settings should be grouped by user-facing function, explain what each option does in plain language, and use controls/styles that match the option type instead of exposing every key as identical text fields.

## What I Already Know

* The current worktree branch is `codex/worktree`.
* The settings panel currently exposes `GhosttyRawConfigEditor`, which renders `TerminalGhosttyConfigCatalog.allKnownKeys` as a searchable list of toggles plus raw text fields.
* The user rejected that UX: "194个都是列表，我要的是以不同功能分类，然后告诉文字是干嘛的，有相对应的样式".
* The relevant files are:
  * `Apps/Conductor/Sources/Conductor/UI/ConductorRootView.swift`
  * `Apps/Conductor/Sources/Conductor/Shared/TerminalGhosttyConfigCatalog.swift`
  * `Apps/Conductor/Sources/Conductor/Shared/TerminalAppearanceModel.swift`
  * `Apps/Conductor/Sources/Conductor/Terminal/TerminalGhosttyConfigBuilder.swift`

## Requirements

* Replace the full raw key list as the primary UI with function-based categories.
* Each category must explain what the controls affect in user-facing text.
* Each setting should use an appropriate control style:
  * toggles for booleans
  * sliders or steppers for bounded numeric values
  * menus or segmented controls for enumerations
  * color swatches/text fields for color values
  * file chooser style actions for paths/images/shaders where feasible
  * compact advanced rows only for uncommon raw overrides
* Preserve advanced access to Ghostty keys, but make it secondary and grouped, not the main experience.
* Avoid claiming "all 194 can be configured" as the headline if most are still raw strings; headline should emphasize categorized, grounded settings.
* Keep SwiftUI state limited to compact metadata and controls; do not route terminal output, scrollback, or rendering data through SwiftUI.

## Acceptance Criteria

* [ ] Settings UI groups Ghostty options by function rather than showing one flat 194-key list.
* [ ] At least core categories exist for typography, cursor, background, selection/mouse, clipboard/paste, shell integration, notifications, and advanced.
* [ ] Rows include short explanatory text describing the user-facing effect.
* [ ] Common settings use typed controls instead of raw text fields.
* [ ] Advanced raw overrides remain available but are visually secondary and grouped by category.
* [ ] The app builds or type-checks to the extent available from the local scripts.

## Out of Scope

* Validating every possible Ghostty value at runtime.
* Implementing every rare platform-specific Ghostty key as a bespoke control.
* Changing terminal rendering architecture.

## Technical Notes

* `GhosttyRawConfigEditor` should likely become a categorized advanced editor or be replaced by a new categorized settings browser.
* Existing override persistence can be reused through `TerminalGhosttyConfigOverride` and `setGhosttyOverrideValue` / `setGhosttyOverrideEnabled`.
* The current `TerminalGhosttyConfigCatalog.groups` already has partial grouping, but the UI still renders a flat list; it needs richer metadata and category presentation.
