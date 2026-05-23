# SwiftUI and Performance Refactor

## Goal

Improve Conductor's maintainability and responsiveness by using the SwiftUI Expert and SwiftUI Pro guidance to audit, split, and optimize the native macOS UI/runtime shell without violating the project's terminal performance boundary. The refactor should reduce broad SwiftUI invalidation, isolate expensive AppKit/WebKit/Ghostty surfaces, and make future feature work less fragile.

## What I Already Know

- The user wants a project refactor because the current code feels disorganized and slow.
- The user clarified that the refactor scope is not only code organization. It must also cover large/bulk rendering, runtime performance, animation cost, and related interaction smoothness.
- The user also wants the refactor to improve structure and code aesthetics: elegant, readable, stable code with appropriate design patterns where they reduce complexity.
- The user clarified that all operations must feel smooth; jank in settings, panels, terminal-adjacent tools, or dense controls is not acceptable. Performance is the first priority, not a polish pass after architecture.
- The project is a high-performance native macOS multi-terminal manager.
- SwiftUI owns product-level shell UI; AppKit owns native integration, responder routing, drag/drop, resize-sensitive surfaces, and stable host views.
- GhosttyKit/libghostty owns terminal rendering, scrollback, cursor movement, transcript text, and high-frequency output.
- Terminal scrollback, transcript text, ANSI rendering, cursor movement, and high-frequency output must not enter SwiftUI state or per-cell SwiftUI rendering.
- Installed and manually loaded SwiftUI skills:
  - `/Users/cses-38/.codex/skills/swiftui-expert-skill/SKILL.md`
  - `/Users/cses-38/.codex/skills/swiftui-pro/SKILL.md`
- Initial code-size scan shows several large files:
  - `Apps/Conductor/Sources/Conductor/UI/ConductorRootView.swift` around 7.2k lines.
  - `Apps/Conductor/Sources/Conductor/UI/FileManagerPanel.swift` around 3.7k lines.
  - `Apps/Conductor/Sources/Conductor/UI/ConductorWindowModel.swift` around 2.7k lines.
  - `Apps/Conductor/Sources/Conductor/UI/ConductorDocumentWorkspaceView.swift` around 2.0k lines.
  - `Apps/Conductor/Sources/Conductor/App/ConductorApp.swift` around 1.7k lines.
- Current working tree has many pre-existing uncommitted changes. This task must not revert or overwrite unrelated user/task work.

## Assumptions

- The first useful refactor should be incremental and reviewable, not a whole-project rewrite.
- Performance wins should prioritize user-visible hot paths: root shell invalidation, split/file/document workspace responsiveness, panel toggles, resize, and terminal-adjacent focus/geometry updates.
- If a change makes the code cleaner but a common interaction still feels stuck, laggy, or heavy, the performance issue remains unsolved.
- Large-file decomposition is useful only when it preserves behavior and reduces invalidation or ownership confusion.
- Bulk rendering problems may exist in both SwiftUI lists/rows and AppKit/WebKit-backed document/file surfaces. The audit should classify each surface by owner and fix it with the right rendering technology rather than forcing everything through SwiftUI.
- Design patterns should be used pragmatically. Patterns are valuable when they clarify ownership, stabilize APIs, isolate side effects, or make performance boundaries explicit; they should not be introduced as decorative architecture.

## Open Questions

- Which first phase should we prioritize: broad audit/report, UI shell decomposition, performance hot-path fixes, or bulk rendering/animation profiling?

## Requirements

- Use SwiftUI Expert guidance for modern SwiftUI state, view composition, performance, macOS scenes/window styling, and AppKit interop.
- Use SwiftUI Pro guidance for deprecated API checks, data flow, accessibility, maintainability, and performance review.
- Start with a global performance/structure audit that classifies surfaces by risk and recommends a phased refactor sequence.
- Treat user-visible interaction smoothness as the top-level requirement: opening panels, switching settings sections, scrolling dense lists, toggling controls, typing into fields, workspace switching, pane resizing, and tray reveal must all feel immediate.
- Improve architecture and code elegance alongside performance: smaller cohesive files, clear ownership boundaries, readable names, narrow value props, stable display models, focused stores/coordinators, and explicit side-effect boundaries.
- Apply design patterns where they fit the codebase, such as:
  - Display model / snapshot pattern for high-volume UI rows and shell metadata.
  - Coordinator/adapter pattern for AppKit, WebKit, QuickLook, and Ghostty bridge ownership.
  - Store/reducer-like organization where a feature has many actions and derived state, without forcing a new framework.
  - Strategy/table-driven patterns for file type routing, document rendering, settings categories, or command handling when branching logic is sprawling.
  - Factory/builder patterns for expensive runtime surfaces or configuration objects where construction must be deduplicated and testable.
- Include large/bulk rendering paths in the refactor scope, including long file previews, large file-tree snapshots, large workspace/tab lists, notification feeds, settings rows, document previews, and any repeated SwiftUI row or card surface.
- Explicitly include Settings > Terminal page jank in scope. The terminal settings page must not mount a large tree of complex SwiftUI controls all at once if that causes slow section switching, scrolling, or control interaction.
- Include animation and transition performance in the refactor scope, especially panel open/close, file tray reveal, workspace switching, tab transitions, split resize, hover effects, and any blur/material/scale/matched-geometry effects that can invalidate large subtrees.
- Classify each performance issue by ownership: SwiftUI metadata UI, AppKit bridge, WebKit document surface, QuickLook/native preview surface, Ghostty terminal surface, or background model/store work.
- Preserve the project rule that terminal output and scrollback never enter SwiftUI observable state.
- Keep stable AppKit host identity for Ghostty, WebKit, QuickLook, and other expensive surfaces.
- Avoid broad rewrites that make existing dirty work impossible to review.
- Prefer small, sequenced changes with clear verification after each phase.
- For every audit item that changes product code, rebuild/launch the latest app immediately and
  drive the affected interaction directly before moving to the next item.
- The agent owns the verification loop: operate the app, inspect the behavior, and fix any
  regression found instead of asking the user to recover or confirm basic correctness.
- After all selected items are complete, run the full Conductor verification gate and document
  any uncovered manual checks or weak assertions honestly.
- Small interaction details are in scope for verification, including panel dismissal, selected
  rows, unread badges, focus restoration, theme propagation, keyboard shortcuts, scroll behavior,
  hover/animation smoothness, and terminal prompt visibility.

## Acceptance Criteria

- [x] A scoped refactor plan identifies the highest-risk/highest-return areas before code changes.
- [x] The audit states that performance and smooth interaction are the first product requirement.
- [x] Bulk rendering surfaces are inventoried and ranked by expected user-visible cost.
- [x] Settings > Terminal page jank is explicitly tracked as a P0 performance surface.
- [x] Animation/transition hotspots are inventoried and ranked by expected user-visible cost.
- [x] The first implementation phase touches a bounded set of files and preserves behavior.
- [x] The selected area has clearer module/file boundaries after refactor, not only faster code.
- [x] Any introduced pattern has an obvious local purpose and removes real complexity.
- [x] SwiftUI state ownership and view decomposition improve in the selected area.
- [x] No terminal transcript/output rendering is moved into SwiftUI state.
- [x] Existing AppKit/Ghostty/WebKit surface identity remains stable.
- [x] Project verification runs at the appropriate risk level, at minimum the known Conductor build/check command if available.

## Definition of Done

- Tests/checks added or updated where appropriate.
- Lint/type-check/build gate is run or the blocker is documented.
- Spec updates are considered for any newly discovered project conventions.
- User-owned unrelated dirty files are left untouched.

## Out of Scope

- Replacing GhosttyKit/libghostty terminal rendering.
- Building a custom terminal renderer.
- Reformatting or rewriting the whole project in one pass.
- Introducing third-party frameworks without explicit user approval.
- Changing product behavior unless it is necessary for the selected refactor.
- Replacing all large rendering surfaces with SwiftUI. The correct owner may be AppKit, WebKit, QuickLook, or Ghostty depending on the content.
- Forcing a rigid architecture such as MVVM, VIPER, Redux, or TCA across the whole app in one task.

## Technical Notes

- First audit artifact:
  - `research/performance-surface-audit.md`
- First implementation phase:
  - Extracted notification panel UI into `Apps/Conductor/Sources/Conductor/UI/NotificationPanelView.swift`.
  - Introduced `NotificationPanelSnapshot` and `NotificationPanelRowSnapshot` so the panel receives compact display data instead of directly observing all notification/workspace/model state in the row tree.
  - Promoted `FloatingPanelHeader` from file-private to module-visible so extracted floating panels can reuse the shared header instead of duplicating it.
  - `swiftc -parse` passed across `Sources/Conductor` and `Sources/ConductorCore`.
  - `swift build` could not reach source compilation because SwiftPM failed while linking the package manifest under the local CommandLineTools toolchain.
- Second implementation phase:
  - Introduced `WorkspaceChromeSnapshot` and `WorkspaceFileTabDisplayModel` in `Apps/Conductor/Sources/Conductor/UI/ConductorRootView.swift`.
  - `ConductorRootView` now derives workspace chrome data once per shell pass and injects it into `ConductorSidebar`, `ConductorToolbar`, and `WorkspaceTabStrip`.
  - `ConductorSidebar`, `ConductorToolbar`, and `WorkspaceTabStrip` no longer create separate `@ObservedObject` subscriptions to `ConductorWindowModel`; they keep the shared model reference for commands while reading compact display state from the snapshot.
  - Sidebar and top tab strip now share one precomputed workspace row list, workspace ID list, unread count, file-tab dirty/selection state, and terminal/split counts instead of each body path rescanning model state.
  - `swiftc -parse` passed across `Sources/Conductor` and `Sources/ConductorCore`.
  - Fixed Swift 6 actor-isolation issues by marking snapshot initializers that read `ConductorWindowModel` as `@MainActor`.
  - `./Scripts/check-conductor.sh` passed from `Apps/Conductor`, including debug build, `ConductorModelCheck`, scenario checks, stress checks, release build, and Trellis context validation.
- Third implementation phase:
  - Introduced `FileManagerDisplaySnapshotBuilder` in `Apps/Conductor/Sources/Conductor/UI/FileManagerPanel.swift`.
  - Moved recursive file-tree row expansion, known-row collection, search filtering, and kind filtering out of `FileManagerPanelStore.displaySnapshot`'s body-access path into a pure builder.
  - `FileManagerPanelStore` now holds a stored `displaySnapshot` and rebuilds it when tree/search/filter inputs change, so `FileManagerPanel.body` reads a compact value instead of triggering recursive snapshot derivation.
  - Added a no-op guard for repeated kind-filter selections.
  - `swiftc -parse` passed across `Sources/Conductor` and `Sources/ConductorCore`.
  - `./Scripts/check-conductor.sh` passed from `Apps/Conductor`, including debug build, `ConductorModelCheck`, scenario checks, stress checks, release build, and Trellis context validation.
- Fourth implementation phase:
  - Added an AppKit-backed `FileManagerSourcePreviewTextHost` for large file-manager text previews in `Apps/Conductor/Sources/Conductor/UI/FileManagerPanel.swift`.
  - Small text previews still use the existing SwiftUI line rows; previews above the line threshold, or truncated reads, now render inside a stable read-only `NSTextView` hosted by `NSViewRepresentable`.
  - The AppKit host deduplicates text and style updates before touching `NSTextView`, preserving a bounded SwiftUI surface while allowing selectable monospaced preview text with line-number prefixes.
  - `swiftc -parse` passed across `Sources/Conductor` and `Sources/ConductorCore`.
  - `./Scripts/check-conductor.sh` passed from `Apps/Conductor`, including debug build, `ConductorModelCheck`, scenario checks, stress checks, release build, and Trellis context validation.
- Fifth implementation phase:
  - Added an AppKit-backed `FileManagerTablePreviewHost` for large CSV/TSV previews in `Apps/Conductor/Sources/Conductor/UI/FileManagerPanel.swift`.
  - Small table previews still use the existing SwiftUI cell renderer; previews above the cell-count threshold, or truncated reads, now render inside a stable `NSTableView` hosted by `NSViewRepresentable`.
  - The AppKit table host deduplicates document, column, and style updates, rebuilds columns only when column count changes, and preserves copy-cell/copy-row context menu actions.
  - Fixed Swift 6 AppKit actor-isolation warnings by keeping table column rebuilds on `@MainActor`.
  - `swiftc -parse` passed across `Sources/Conductor` and `Sources/ConductorCore`.
  - `./Scripts/check-conductor.sh` passed from `Apps/Conductor`, including debug build, `ConductorModelCheck`, scenario checks, stress checks, release build, and Trellis context validation.
- Sixth implementation phase:
  - Added AppKit-backed `FileManagerKeyValuePreviewHost` and `FileManagerStructuredPreviewHost` for large key-value and structured data previews in `Apps/Conductor/Sources/Conductor/UI/FileManagerPanel.swift`.
  - Small key-value/structured previews still use the existing SwiftUI row renderers; previews above the row threshold, or truncated reads, now render inside stable `NSTableView` hosts.
  - The AppKit hosts deduplicate document/style updates, build fixed columns once, preserve row indentation for structured paths, and keep the existing copy key/value/path/line context menu actions.
  - Reused the existing table cell host with configurable insets so structured indentation stays inside AppKit rather than forcing per-row SwiftUI layout.
  - `swiftc -parse` passed across `Sources/Conductor` and `Sources/ConductorCore`.
  - `./Scripts/check-conductor.sh` passed from `Apps/Conductor`, including debug build, `ConductorModelCheck`, scenario checks, stress checks, release build, and Trellis context validation.
- Seventh implementation phase:
  - Updated `ConductorWorkspaceSourceTextView` in `Apps/Conductor/Sources/Conductor/UI/ConductorFileWorkspaceView.swift` so AppKit owns rapid `NSTextView` edits between flushes instead of writing the full file text back into SwiftUI state on every keystroke.
  - Added a coalesced text snapshot path for normal editing and an explicit synchronous snapshot token for save/close/unmount so command saves use the current AppKit buffer.
  - Reused the existing `editorSnapshotToken` / `pendingSaveRequest` shape to request current text from the mounted source editor, with fallback to SwiftUI's last snapshot when the editor is not mounted in Markdown preview-only mode.
  - Updated `.trellis/spec/frontend/component-guidelines.md` with the workspace editor convention: AppKit may own the live buffer, SwiftUI receives coalesced snapshots plus synchronous save/close snapshots.
  - `swiftc -parse` passed across `Sources/Conductor` and `Sources/ConductorCore`.
  - `./Scripts/check-conductor.sh` passed from `Apps/Conductor`, including debug build, `ConductorModelCheck`, scenario checks, stress checks, release build, and Trellis context validation.
- Eighth implementation phase:
  - Updated shared `ConductorMotion` in `Apps/Conductor/Sources/Conductor/UI/ConductorDesign.swift` so floating panel reveal transitions no longer use blur or full-panel scale; panel/search reveal now uses cheap opacity plus a small transform.
  - Lightened row/tab transitions to opacity-only and changed notification row removal to opacity-only.
  - Added count-gated motion helpers (`rowTransition(itemCount:)`, `notificationRowTransition(itemCount:)`, and `list(itemCount:)`) with a shared animated collection limit.
  - Applied the count-gated helpers to Command Center results, Workspace Overview cards, Sidebar rows, and Notification Center rows so large filtered collections do not schedule per-row insertion/list animations.
  - Updated `.trellis/spec/frontend/component-guidelines.md` with the heavy-panel collection animation convention.
  - `swiftc -parse` passed across `Sources/Conductor` and `Sources/ConductorCore`.
  - `./Scripts/check-conductor.sh` passed from `Apps/Conductor`, including debug build, `ConductorModelCheck`, scenario checks, stress checks, release build, and Trellis context validation.
- Ninth implementation phase:
  - Extended `SettingsPanelSnapshot` usage in `Apps/Conductor/Sources/Conductor/UI/ConductorRootView.swift` so the Settings overview, interface, terminal shell, typography, background, selection, clipboard, notifications, keyboard, cursor, proxy, AI, and theme sections read display values from a compact snapshot.
  - Kept the shared `ConductorWindowModel` reference for commands, setters, and side-effectful actions while moving broad display reads away from repeated direct model access inside settings row bodies.
  - Converted the advanced Ghostty functional config browser helpers to take a `TerminalRendererPreferences` snapshot plus override action closures, so row/section helpers do not directly read `model.appearance` for display state.
  - Preserved existing settings behavior and bindings while reducing the amount of observable model state that the open Settings panel depends on during normal body recomputation.
  - `swiftc -parse` passed across `Sources/Conductor` and `Sources/ConductorCore`.
  - Per user preference, skipped the full Conductor gate for this local panel-only refactor and reserved full checks for larger or cross-layer changes.
- Tenth implementation phase:
  - Reworked Settings > Terminal in `Apps/Conductor/Sources/Conductor/UI/ConductorRootView.swift` from one long dashboard into a lightweight local category switcher.
  - Added `TerminalSettingsSection` with typography, display, selection, and input categories so the page mounts only the currently active dense control group.
  - Removed large-subtree animation from terminal settings category changes by applying a nil-animation transaction and using `ConductorMotion.withoutAnimation` for local category selection.
  - Preserved all existing terminal setting controls and command callbacks while reducing first-entry and category-switch SwiftUI view construction.
  - `swiftc -parse` passed across `Sources/Conductor` and `Sources/ConductorCore`.
- Eleventh implementation phase:
  - Redesigned the Settings visual language in `Apps/Conductor/Sources/Conductor/UI/ConductorRootView.swift` toward a denser macOS inspector style.
  - Reduced card-heavy treatment by making settings groups read as section headers, lightening form surfaces, tightening row heights, and removing filled icon blocks from common settings rows.
  - Reworked the overview from a dashboard grid plus explanatory structure card into a compact grouped summary list with plain jump rows.
  - Made sidebar categories more explicit by renaming sections and showing each section subtitle directly in the sidebar row.
  - `swiftc -parse` passed across `Sources/Conductor` and `Sources/ConductorCore`.
- Twelfth implementation phase:
  - Removed the large theme preview card from the Settings sidebar summary and replaced it with a compact title/status treatment.
  - Replaced the Settings > Terminal category picker row with a clear local navigation rail so terminal subcategories are visible without another nested form/card.
  - Kept the active terminal category as the only mounted dense settings group while making the category structure easier to scan.
  - `swiftc -parse` passed across `Sources/Conductor` and `Sources/ConductorCore`.
- Thirteenth implementation phase:
  - Fixed a Settings theme switching regression by removing the `AppearanceSettingsPanel.equatable()` wrapper so theme/environment changes can flow through the open panel.
  - Replaced the theme card grid with explicit `ThemeOptionRow` selection rows so clicking a theme has a clear command target and current selection indicator.
  - Removed the now-unused `ThemeGalleryCard` implementation.
  - Updated frontend specs with the lesson that Settings controls for global shell preferences are cross-surface commands and must be validated through model mutation, environment propagation, live surface updates, and persistence.
- Fourteenth implementation phase:
  - Fixed delayed sidebar/workspace-tab theme propagation after Settings theme changes by keeping the chrome row/tab `Equatable` optimization but adding theme and font-scale identities to the equality inputs.
  - Preserved the compact snapshot and equatable chrome pattern for normal metadata updates while allowing global appearance environment changes to restyle visible sidebar rows and top tabs immediately.
  - Updated frontend specs with the rule that Equatable shell leaves reading appearance environment must include the relevant appearance identity or avoid `.equatable()`.
- Fifteenth implementation phase:
  - Fixed the actual stale main-chrome path where `ConductorSidebar`, `ConductorToolbar`, and `WorkspaceTabStrip` avoided broad `@ObservedObject` subscriptions but still read `model.theme` / `model.appearance` through the unobserved model reference.
  - Passed `TerminalTheme`, `AppearancePreferences`, and sidebar visibility into those chrome containers as explicit value inputs so Settings theme changes invalidate sidebar and top-tab chrome immediately without reintroducing broad model observation.
  - Updated frontend specs with the rule that performance-isolated chrome containers must receive low-frequency visual state as explicit props instead of reading appearance through an unobserved model reference.
- Sixteenth implementation phase:
  - Added `ToolbarChromeSnapshot` so toolbar command enablement and active states are explicit compact inputs rather than direct reads from an unobserved `ConductorWindowModel` reference.
  - Routed split, zoom, file-manager, workspace-overview, and notification toolbar button display state through the snapshot while preserving command execution through `model.performCommand`.
  - Updated frontend specs with the rule that performance-isolated toolbar chrome must snapshot active/disabled display state just like visual appearance state.
- Seventeenth implementation phase:
  - Added `WorkspaceOverviewSnapshot` so the Workspace Overview floating panel reads workspace list, selected workspace, notification counts, and chrome clarity from a compact value input.
  - Removed the panel's direct `@ObservedObject` subscription to `ConductorWindowModel`; the panel keeps the model only as a command reference for close/select actions.
  - Updated frontend specs to cover Workspace Overview and other heavy floating panels in the compact snapshot rule, preventing unrelated terminal metadata changes from broadly invalidating card grids.
- Eighteenth implementation phase:
  - Added `CommandPaletteSnapshot` so Command Center reads subtitle, chrome clarity, and command rows from a compact value input.
  - Removed `CommandPaletteView`'s direct `@ObservedObject` subscription to `ConductorWindowModel`; the panel keeps the model only as a command coordinator for hide/perform actions.
  - Converted `CommandPaletteItem` into an `Equatable` value row with a `ConductorShellCommand`, disabled state, shortcut, keywords, and precomputed lowercase search text instead of embedding per-row action closures.
  - Kept shortcut-guide rows projected from the same command catalog so the command surface and discoverability surface stay synchronized.
  - Updated frontend specs with the Command Center value-row rule.
- Nineteenth implementation phase:
  - Added `TerminalPaneChromeSnapshot` and `TerminalTabDisplayModel` in `Apps/Conductor/Sources/Conductor/UI/SplitNodeView.swift` so terminal pane/tab chrome reads compact value inputs for focus, appearance, unread/metadata badges, drop targets, drag state, split capability, context-menu disabled state, and flash tokens.
  - Removed direct `@ObservedObject` subscriptions from `TerminalPaneView`, `StableTerminalTabStrip`, and `TerminalTabButton`; they keep `ConductorWindowModel` only as a command coordinator for terminal surface lookup, focus, selection, close, rename, drag/drop, and context-menu actions.
  - Preserved `TerminalSurfaceRepresentable` identity and Ghostty/AppKit surface ownership; the selected terminal still resolves through `model.surface(for:)` and no theme/appearance `.id(...)` recreation was introduced.
  - Added theme/font-scale identity to `TerminalTabButtonContent` equality inputs so global appearance changes restyle terminal tab labels immediately while keeping the row-content equality optimization.
  - Updated frontend specs with the terminal pane/tab chrome snapshot convention.
- Twentieth implementation phase:
  - Removed the remaining unnecessary `@ObservedObject` subscriptions from `SplitPairView` and `AppKitSplitPairView`; the split pair bridge now keeps the window model as a plain coordinator reference while the recursive `SplitNodeView` roots remain the observation boundary.
  - Preserved explicit theme input for divider colors and kept the AppKit split hosting/signature path unchanged.
- Twenty-first implementation phase:
  - Added `ConductorFileWorkspaceSnapshot` so the file workspace receives selected file tab, search generations, save request generations, terminal font size, and document layout revision as compact value inputs.
  - Removed `ConductorFileWorkspaceView`'s direct `@ObservedObject` subscription and changed `ConductorWorkspaceFileEditorView` to read save tokens, font size, and layout revision from explicit props instead of the broad window model.
  - Added a matching snapshot for the workspace content tab bar so terminal/file tab display state is value-driven if that surface is reattached later.
- Twenty-second implementation phase:
  - Replaced `NotificationPanelRootView`'s broad `@ObservedObject` subscription with a `NotificationPanelStore` that publishes only notification snapshot, theme, and appearance values needed by the detached notification window.
  - Scoped notification panel invalidation to `notifications`, `workspaces`, `theme`, and `appearance`, preserving model command routing for close, jump, clear, open, and test-notification actions.
  - Reduced the remaining UI-wide `@ObservedObject var model` boundaries to the main root and split root.
- Twenty-third implementation phase:
  - Added precomputed identifiable row models to `FilePreviewTextDocument` and `FilePreviewTableDocument` so SwiftUI fallback previews do not allocate `Array(enumerated())` inside `body`.
  - Cached table column count during document construction instead of recomputing it from every render path.
  - Kept large/truncated text and table previews on their existing AppKit host paths; this only tightens the medium-size SwiftUI fallback path.
- Twenty-fourth implementation phase:
  - Added `CommandPaletteFilterResult` and `CommandPaletteFilteredRow` so Command Center search produces rows, section-title markers, enabled-command collections, and animation IDs in one pass.
  - Removed repeated `filteredCommands` access and `Array(filteredCommands.enumerated())` allocation from the command results body.
  - Kept command execution routed through `ConductorShellCommand` and `ConductorWindowModel.performCommand`.
- Twenty-fifth implementation phase:
  - Added `CommandShortcutGuideRowModel` and moved shortcut-guide rows into `SettingsPanelSnapshot` so the Settings command guide does not rebuild catalog rows from `body`.
  - Removed the remaining `Array(enumerated())` usages from `ConductorRootView`, including the theme picker and shortcut guide.
  - Kept theme selection and command discovery routed through the existing model/catalog paths.
- Twenty-sixth implementation phase:
  - Reworked `FileManagerDisplaySnapshotBuilder` to accumulate visible and known rows with inout recursion instead of recursive `flatMap` arrays.
  - Avoided building the full known-row array when there is no file search query; the empty-search path now computes only the known count plus visible rows.
  - Counted displayed files and directories in one pass while constructing the snapshot instead of filtering the rendered rows twice.
- Twenty-seventh implementation phase:
  - Fixed the notification navigation regression introduced while scoping `NotificationPanelRootView`: `ConductorWindowModel.openNotification(_:)` now closes the detached notification panel after focusing the target terminal, marking the notification read, and refreshing the target surface.
  - Captured the behavior contract in frontend specs so notification row actions remain model-level navigation commands rather than partial row-local mutations.
  - Added `CONDUCTOR_NOTIFICATION_AUTORUN` to `check-conductor.sh` so notification clicks must open, close the detached panel, clear unread state, and keep the target terminal focused before the gate passes.
- Twenty-eighth implementation phase:
  - Reworked shared `ConductorMotion` panel timing toward CSS-style fast-out/slow-settle transitions using `.timingCurve(0.16, 1.0, 0.3, 1.0)`.
  - Replaced the prior mostly-opacity floating panel transition with asymmetric transform-based opacity, offset, and subtle scale so Command Center and Workspace Overview slide from the top, Settings slides from the trailing edge, and removal exits in the matching direction.
  - Added `sidebarContentTransition` so expanded/collapsed sidebar rail content slides horizontally instead of crossfading in place, while preserving the existing shell width animation and avoiding terminal surface transforms.
  - Added matching AppKit frame/alpha motion for the detached notification `NSPanel`, including a `@MainActor` completion path that orders the panel out and restores main-window focus after the slide-out finishes.
  - Updated the motion language spec to require CSS-like transform transitions for panels and rails, with reduced-motion and terminal-surface boundaries intact.
- Twenty-ninth implementation phase:
  - Added shared signature motion primitives for more interesting chrome animation: bounded `conductorCascade`, `conductorSignalPulse`, `delivery`, `cascade`, `contentSwap`, and `workspaceSpreadTransition`.
  - Applied cascade entry to Command Center result rows and Notification Center rows, added one-shot signal pulse to unread dots/badges, and changed Workspace Overview card insertion/removal to a spatial spread transition.
  - Kept every signature primitive count-gated and transform-only so terminal hosts, WebKit/QuickLook surfaces, and high-volume text previews remain outside decorative motion.
- Thirtieth implementation phase:
  - Added directional `contentSwapTransition(edge:)` and applied it to Settings sidebar section changes plus Settings > Terminal local category changes.
  - Main Settings sections and terminal subcategories now swap like ordered modules: forward navigation enters from the trailing edge, backward navigation enters from the leading edge, with transform-only opacity/offset/tiny-scale motion.
  - Preserved the Settings performance design by keeping only the active terminal subcategory mounted and avoiding animation on dense form value changes.
- Thirty-first implementation phase:
  - Added shared `conductorFocusSweep(color:cornerRadius:active:trigger:)` motion for focused terminal pane chrome, using a staged border/sweep overlay that never wraps or transforms `TerminalSurfaceRepresentable`.
  - Wired focus navigation and explicit focused-pane flash tokens into `TerminalPaneView` through a compact local trigger so pane focus becomes legible without adding terminal output, cursor, or renderer state to SwiftUI.
  - Verified this product-code item immediately with `swift build`, the focus autorun route, a fresh app bundle launch, and screenshot inspection before moving on.
- Thirty-second implementation phase:
  - Connected the existing terminal tab strip `selectionNamespace` to the selected tab fill through `matchedGeometryEffect`, making terminal tab selection move as a real local capsule instead of only recoloring each tab.
  - Kept model selection unanimated and chrome-local: the visual selected tab updates with `selectionGlide`, while `TerminalSurfaceRepresentable` remains outside matched geometry and identity changes.
  - Verified this item immediately with `swift build`, focus autorun, and layout autorun.
- Thirty-third implementation phase:
  - Removed the terminal pane focus sweep visual after design review; focused pane feedback now uses only a restrained chrome ring opacity/line-width settle.
  - Renamed the shared helper from `conductorFocusSweep` to `conductorFocusRing` so future motion work does not reintroduce traveling light around terminal panes by accident.
  - Kept the Ghostty/AppKit terminal surface untouched and preserved explicit focused-pane flash behavior.
- Thirty-fourth implementation phase:
  - Moved the sidebar workspace selected-row matched background out of `WorkspaceSidebarRowContent.equatable()` and onto the row container so selection glide is not trapped inside an equality/cache boundary.
  - Removed unused selection namespace/value inputs from the equatable content leaf and dropped the transaction-disabled subtree that was suppressing row selection motion.
  - Verified this item immediately with `swift build`, workspace autorun, and focus autorun before continuing.
- Thirty-fifth implementation phase:
  - Added `commandPaletteVisible` to `ToolbarChromeSnapshot` and wired it to the Command Center toolbar button's active state.
  - Kept toolbar panel visibility inputs value-driven rather than reading unobserved model flags from the button subtree.
  - Verified this item immediately with `swift build` and shell-panel autorun.
- Project specs read:
  - `.trellis/spec/guides/high-performance-terminal-roadmap.md`
  - `.trellis/spec/frontend/component-guidelines.md`
  - `.trellis/spec/frontend/state-management.md`
  - `.trellis/spec/frontend/quality-guidelines.md`
- Relevant SwiftUI Expert references to consult during implementation:
  - `references/latest-apis.md`
  - `references/state-management.md`
  - `references/view-structure.md`
  - `references/performance-patterns.md`
  - `references/macos-scenes.md`
  - `references/macos-window-styling.md`
  - `references/macos-views.md`
- Relevant SwiftUI Pro references to consult during implementation:
  - `references/api.md`
  - `references/views.md`
  - `references/data.md`
  - `references/performance.md`
  - `references/hygiene.md`
