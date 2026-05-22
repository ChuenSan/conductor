# Coverage Matrix

Status legend:

- Reviewed: audited with notes.
- Vendor bounded: third-party/minified asset reviewed for integration, loading, and performance-use risks only.
- Deferred: intentionally not reviewed with a written reason.

| Status | File | Module | Notes |
| --- | --- | --- | --- |
| Reviewed | `Apps/Conductor/Sources/Conductor/App/AgentCLIStatusDetector.swift` | App | Small process-based CLI detector. Risk: `Process` + `readDataToEndOfFile` should never run on a hot UI path. Current use appears settings/status oriented. |
| Reviewed | `Apps/Conductor/Sources/Conductor/App/CodexNotificationHookInstaller.swift` | App | Hook install file IO is explicit workflow, not hot path. Risk: config reads/writes should stay off panel animations. |
| Reviewed | `Apps/Conductor/Sources/Conductor/App/ConductorAgentHookBridge.swift` | App | CLI bridge path, standard input read is process mode. No UI hot-path risk. |
| Reviewed | `Apps/Conductor/Sources/Conductor/App/ConductorApp.swift` | App | Large lifecycle/menu/automation delegate. P2: runtime app delegate mixed with smoke/stress automation, focus routing, notification window, and test writers; extract automation runners. |
| Vendor bounded | `Apps/Conductor/Sources/Conductor/Resources/DocumentViewer/vendor/highlight.min.js` | Document vendor | Bundled into every document HTML today; should be loaded only for code/markdown requiring highlight. |
| Vendor bounded | `Apps/Conductor/Sources/Conductor/Resources/DocumentViewer/vendor/katex-auto-render.min.js` | Document vendor | Bundled into every document HTML; should be conditional for TeX/math Markdown. |
| Vendor bounded | `Apps/Conductor/Sources/Conductor/Resources/DocumentViewer/vendor/katex.min.css` | Document vendor | Style is read/inlined per HTML build; should be cached. |
| Vendor bounded | `Apps/Conductor/Sources/Conductor/Resources/DocumentViewer/vendor/katex.min.js` | Document vendor | Bundled into every document HTML; should be conditional. |
| Vendor bounded | `Apps/Conductor/Sources/Conductor/Resources/DocumentViewer/vendor/mammoth.browser.min.js` | Document vendor | Large Word parser; should only load for `.docx`. |
| Vendor bounded | `Apps/Conductor/Sources/Conductor/Resources/DocumentViewer/vendor/markdown-it.min.js` | Document vendor | Required for Markdown, but should be cached and not injected for PDF/image/native views. |
| Vendor bounded | `Apps/Conductor/Sources/Conductor/Resources/DocumentViewer/vendor/mermaid.min.js` | Document vendor | Largest vendor file by line count; only load when Markdown contains Mermaid blocks. |
| Vendor bounded | `Apps/Conductor/Sources/Conductor/Resources/DocumentViewer/vendor/papaparse.min.js` | Document vendor | CSV parser; load only for table files. |
| Vendor bounded | `Apps/Conductor/Sources/Conductor/Resources/DocumentViewer/vendor/pdf.min.js` | Document vendor | PDF parser; load only for PDF and prefer file/native path for large docs. |
| Vendor bounded | `Apps/Conductor/Sources/Conductor/Resources/DocumentViewer/vendor/pdf.worker.min.js` | Document vendor | Base64 worker string rebuilt into every HTML; cache and conditionalize. |
| Vendor bounded | `Apps/Conductor/Sources/Conductor/Resources/DocumentViewer/vendor/purify.min.js` | Document vendor | Security dependency for HTML/Markdown; cache script. |
| Vendor bounded | `Apps/Conductor/Sources/Conductor/Resources/DocumentViewer/vendor/xlsx.full.min.js` | Document vendor | Spreadsheet parser; only load for spreadsheet payloads. |
| Reviewed | `Apps/Conductor/Sources/Conductor/Shared/AppearancePreferences.swift` | Shared | Value models. Risk is broad `appearance` publish causing shell/settings invalidation, not local code. |
| Reviewed | `Apps/Conductor/Sources/Conductor/Shared/ConductorDiagnostics.swift` | Shared | Log file IO bounded and sync variant used for crash/termination. Keep off high-frequency loops. |
| Reviewed | `Apps/Conductor/Sources/Conductor/Shared/ConductorLog.swift` | Shared | OSLog wrappers. Low risk. |
| Reviewed | `Apps/Conductor/Sources/Conductor/Shared/ConductorMainThreadWatchdog.swift` | Shared | Useful instrumentation. Needs workflow labels/counters for actionable profiling. |
| Reviewed | `Apps/Conductor/Sources/Conductor/Shared/TerminalAppearanceModel.swift` | Shared | Value models. Risk is renderer preference changes reapplying surfaces broadly. |
| Reviewed | `Apps/Conductor/Sources/Conductor/Shared/TerminalColorPlatform.swift` | Shared | Tiny color bridge. Low risk. |
| Reviewed | `Apps/Conductor/Sources/Conductor/Shared/TerminalFontAvailability.swift` | Shared | Installed font cache. Refresh must stay explicit; avoid querying on every settings row body. |
| Reviewed | `Apps/Conductor/Sources/Conductor/Shared/TerminalFontLibrary.swift` | Shared | Font download/extract/register path. P1/P2 only if invoked from settings without progress isolation; `Process.waitUntilExit` should remain off main path. |
| Reviewed | `Apps/Conductor/Sources/Conductor/Shared/TerminalGhosttyConfigCatalog.swift` | Shared | Static catalog/search index. P1: settings search should cache filtered product groups by normalized query. |
| Reviewed | `Apps/Conductor/Sources/Conductor/Shared/TerminalTheme.swift` | Shared | Large static theme definitions. Low runtime risk except broad theme publishes. |
| Reviewed | `Apps/Conductor/Sources/Conductor/Shared/WorkspacePersistence.swift` | Shared | P2: synchronous load/save implementation. Model debounces saves, but encode/write should move to background actor as workspace count grows. |
| Reviewed | `Apps/Conductor/Sources/Conductor/Terminal/GhosttyAppRuntime.swift` | Terminal | Ghostty app bridge is correct direction. Risk: action callbacks dispatch many small main-actor updates; metadata store should remain coalesced and isolated. |
| Reviewed | `Apps/Conductor/Sources/Conductor/Terminal/TerminalGhosttyConfigBuilder.swift` | Terminal | Small config builder. Low risk. |
| Reviewed | `Apps/Conductor/Sources/Conductor/Terminal/TerminalHostView.swift` | Terminal | AppKit input host. P2: geometry sync is duplicated with container; cursor/focus behavior depends on coordinator not yet centralized. |
| Reviewed | `Apps/Conductor/Sources/Conductor/Terminal/TerminalSurface.swift` | Terminal | Ghostty surface owner. P2: retained C string buffer and repeated geometry/focus refresh need counters and tighter ownership rules. |
| Reviewed | `Apps/Conductor/Sources/Conductor/Terminal/TerminalSurfaceRepresentable.swift` | Terminal | Stable AppKit host. P1/P2: focus restoration and geometry scheduling are critical; should be governed by central focus and frame-coalescing policy. |
| Reviewed | `Apps/Conductor/Sources/Conductor/UI/ConductorAsyncImage.swift` | UI | P2: shared image cache has no count/cost limit; full data read/decode before display. |
| Reviewed | `Apps/Conductor/Sources/Conductor/UI/ConductorContextSearchControls.swift` | UI | P1: AppKit text field focus token races with terminal focus restore and hidden bridge focus. Needs focus coordinator. |
| Reviewed | `Apps/Conductor/Sources/Conductor/UI/ConductorDesign.swift` | UI | Motion/tooltips/cursors shared here. P1: motion primitives are good but large-overlay presentation is not unified. P3: clickable cursor policy missing. |
| Reviewed | `Apps/Conductor/Sources/Conductor/UI/ConductorDocumentWorkspaceView.swift` | UI | P1: WebView identity/reload and full vendor inlining are major preview/Markdown cost. |
| Reviewed | `Apps/Conductor/Sources/Conductor/UI/ConductorFileWorkspaceView.swift` | UI | P1: hidden editors remain mounted; Markdown preview WebView reloads; external watchers/search/autosave multiply by open file count. |
| Reviewed | `Apps/Conductor/Sources/Conductor/UI/ConductorImageWorkspaceView.swift` | UI | P2: large images use full decode/cache; shortcut bridge focus should be coordinated. |
| Reviewed | `Apps/Conductor/Sources/Conductor/UI/ConductorKeyboardShortcutBridge.swift` | UI | P2: hidden first-responder bridge is useful but can steal/compete with search/editor focus. |
| Reviewed | `Apps/Conductor/Sources/Conductor/UI/ConductorNativePreviewWorkspaceView.swift` | UI | QuickLook resize freeze is useful. P2: unify live-resize policy with WebView/source/terminal. |
| Reviewed | `Apps/Conductor/Sources/Conductor/UI/ConductorPreviewFixtures.swift` | UI | Preview-only fixtures. No production hot-path risk. |
| Reviewed | `Apps/Conductor/Sources/Conductor/UI/ConductorRootView.swift` | UI | Largest UI file. P1: root observes broad model; command/settings/overview/search/sidebar/tab strips recompute from shared state; motion strategies differ. |
| Reviewed | `Apps/Conductor/Sources/Conductor/UI/ConductorShellCommand.swift` | UI | Command router. Low direct perf risk, but depends on broad model capability checks. |
| Reviewed | `Apps/Conductor/Sources/Conductor/UI/ConductorWindowModel.swift` | UI | P1: broad `@Published` surface is the central invalidation problem. Split model into focused stores/snapshots. |
| Reviewed | `Apps/Conductor/Sources/Conductor/UI/FileManagerPanel.swift` | UI | P1: needs true virtual scrolling/data snapshot caching; store has too many published concerns; preview and row state should split. |
| Reviewed | `Apps/Conductor/Sources/Conductor/UI/SplitNodeView.swift` | UI | P2: AppKit split is correct, but root updates and geometry sync can still compete during drag. Hover/cursor behavior mostly localized. |
| Reviewed | `Apps/Conductor/Sources/ConductorCore/Shared/IDs.swift` | Core | Tiny value IDs. Low risk. |
| Reviewed | `Apps/Conductor/Sources/ConductorCore/Workspace/AgentIntegrationModel.swift` | Core | Static catalog. Low risk. |
| Reviewed | `Apps/Conductor/Sources/ConductorCore/Workspace/TerminalNotificationModel.swift` | Core | P2: snapshot rebuilt on every notification mutation; bound and/or incrementalize as notification volume grows. |
| Reviewed | `Apps/Conductor/Sources/ConductorCore/Workspace/WorkspaceModel.swift` | Core | Pure value layout model. Solid. Risk: recursive leaf scans are fine at current max panes but should stay bounded. |
| Reviewed | `Apps/Conductor/Sources/ConductorModelCheck/main.swift` | Check | Test harness only. Good coverage for model semantics; needs future perf-focused checks/signpost assertions. |
