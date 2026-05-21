# Optimize settings popup performance

## Goal

Make the settings popup feel immediate and lightweight. Opening, closing, switching sections, scrolling, and typing into settings search must not stall terminal rendering or make the whole app feel heavy.

## What I Already Know

* The user reports serious performance problems, especially around popups and the settings popup.
* `AppearanceSettingsPanel` is mounted directly in `ConductorRootView` as a root overlay when `model.settingsPanelVisible` is true.
* The panel uses `@ObservedObject var model: ConductorWindowModel`, and many nested settings controls also observe the full model.
* The settings content is large and currently lives in `ConductorRootView.swift`, including overview, interface, terminal, shell/proxy, AI, command, theme, and Ghostty config UI.
* `detailContent` wraps the selected settings page in an animated `VStack` with `.id(selectedSection)` and opacity transition.
* The panel reveal transition includes a blur modifier, which can be expensive on a large SwiftUI subtree.
* Ghostty settings search filters product groups synchronously and calls `TerminalGhosttyConfigCatalog.description(for:)` for many keys while typing.
* Settings hover and selection use local `@State`, matched geometry, overlays, strokes, and animation, increasing the number of small invalidations.
* Terminal runtime rules require terminal output/rendering to stay out of SwiftUI state and avoid expensive main-thread work.

## Assumptions

* The main problem is not one single visual bug; it is accumulated main-thread SwiftUI work when mounting and updating a large popup.
* We should keep the current settings functionality, but change how it is built/rendered so inactive sections and heavy lists do not participate in every render pass.
* The solution should favor native macOS-feeling responsiveness over decorative animation.

## Requirements

* Opening settings should avoid constructing heavy inactive settings pages.
* Closing and switching settings sections should avoid triggering large root-view animations.
* Settings search should avoid synchronous repeated full-catalog filtering on every keystroke.
* Hover and selection affordances should stay usable, but not steal clicks or introduce sluggish delayed interaction.
* Long terminal output should remain responsive while settings is opened, closed, and navigated.
* Existing controls and persisted settings behavior must keep working.

## Acceptance Criteria

* [ ] Opening Settings with `Cmd-,` or toolbar action feels immediate in the running app.
* [ ] Switching between settings sections does not visibly freeze or stutter.
* [ ] Typing in Ghostty settings search remains responsive and does not rebuild unrelated settings sections.
* [ ] Terminal output continues while settings is open without noticeable app-wide stalls.
* [ ] Existing check script still passes: `cd Apps/Conductor && ./Scripts/check-conductor.sh`.
* [ ] Dirty user files unrelated to this task, especially `.idea/workspace.xml`, are not touched.

## Out of Scope

* Redesigning the full visual language of settings.
* Removing settings functionality.
* Changing Ghostty terminal renderer ownership.
* Large architectural rewrite of all app popups unless needed for the settings fix.

## Technical Notes

* Likely files:
  * `Apps/Conductor/Sources/Conductor/UI/ConductorRootView.swift`
  * `Apps/Conductor/Sources/Conductor/UI/ConductorWindowModel.swift`
  * `Apps/Conductor/Sources/Conductor/UI/ConductorDesign.swift`
  * `Apps/Conductor/Sources/Conductor/Shared/TerminalGhosttyConfigCatalog.swift`
* Candidate improvements:
  * Remove blur from large panel transitions, or use a cheaper transition for settings.
  * Split settings panel into smaller view files/components so only the active section observes the data it needs.
  * Replace broad `@ObservedObject model` in heavy settings rows with smaller value snapshots and action closures where possible.
  * Precompute/search-index Ghostty config metadata and debounce or cache search results.
  * Use `LazyVStack` for long settings pages and heavy Ghostty config rows.
  * Avoid `.id(selectedSection)` + animated full content replacement if it causes full subtree churn.
