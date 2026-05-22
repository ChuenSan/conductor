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
