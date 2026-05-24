# Web Tabs Design

## Status

Approved for implementation direction by the user on 2026-05-25. Build a more complete
Conductor-native web tab feature, informed by open-source browser implementations, without
copying GPL-licensed code into the project.

## Context

Conductor already has three important foundations for web tabs:

- A workspace shell that can switch between terminal content and file workspace content.
- A top workspace tab strip that already supports non-terminal file tabs.
- Historical web-tab commits that added a small `WKWebView` surface, address bar, and
  commands, then later removed that browser surface during search rewrite work.

The user wants a richer web tab capability than the historical lightweight prototype. The
goal is not to become a full browser product, but to make Conductor useful for developer
workflows that regularly jump between terminal agents, local preview servers, docs,
GitHub, dashboards, and issue trackers.

## Open-Source Research

### DuckDuckGo Apple Browsers

Repository: https://github.com/duckduckgo/apple-browsers

DuckDuckGo's Apple browsers are Swift/AppKit/WebKit-based and Apache-2.0 licensed. Their
macOS code includes mature tab lifecycle ideas such as:

- `TabCollection` for append, insert, move, replace, and remove behavior.
- `TabCollectionViewModel` for selection and close-selection policy.
- A custom `WebView` subclass for WebKit interaction events, zoom, media cleanup, and
  menu/full-screen edge cases.
- `WebViewContainerView` for stable AppKit ownership around WebKit full-screen behavior.

The code is too integrated with DuckDuckGo services, feature flags, privacy config,
history, extensions, and app delegate globals to copy wholesale. It is appropriate to
borrow architecture patterns or small Apache-2.0 snippets only when the copied code is
isolated, attributed, and modified notices are preserved.

### Min Browser

Repository: https://github.com/minbrowser/min

Min is Apache-2.0 and has strong UX ideas around minimal browser chrome, tasks/tab groups,
and keyboard-driven navigation. It is Electron/JavaScript, so it is useful for UX
reference but not a good source for Conductor Swift/AppKit implementation code.

### Ora and Nook

Repositories:

- https://github.com/the-ora/browser
- https://github.com/nook-browser/Nook

Both are macOS browser projects with Swift/WebKit or SwiftUI browser UX ideas. Both are
GPL-3.0. Their code must not be copied into Conductor unless Conductor intentionally adopts
GPL-compatible distribution obligations. They may be used only as product inspiration.

## Goals

1. Add first-class web content tabs alongside file tabs and terminal workspaces.
2. Use native `WKWebView` through a stable AppKit bridge, not a JavaScript browser runtime.
3. Keep WebKit process/state out of SwiftUI state. SwiftUI owns compact metadata only.
4. Preserve terminal performance: web tab changes must not recreate Ghostty surfaces or
   store terminal output.
5. Support a practical developer browser set:
   - New web tab.
   - Address/search submission.
   - Back, forward, reload, stop.
   - Loading progress and error display.
   - Page title and URL sync into tab chrome.
   - Favicon display when discoverable.
   - Open externally.
   - New-window / target-blank handling.
   - Downloads routed to the system download location.
   - Localhost and bare-domain address resolution.
   - Command, menu, and toolbar entry.
6. Keep implementation testable with model checks for pure behavior.

## Non-Goals

- Browser extensions.
- Password manager integration.
- Ad/tracker blocking.
- Full browsing history UI.
- Bookmark manager.
- Sync, profiles, or private windows.
- Replacing the user's default browser.
- Running a Chromium/Electron/CEF runtime.
- Copying GPL-licensed code.

## Product Behavior

### Opening Web Tabs

Users can create a blank web tab from toolbar/command palette/menu. Blank web tabs focus
the address field. Submitting an address:

- Opens `http://localhost...` and loopback addresses as HTTP.
- Opens full `http://` and `https://` URLs directly.
- Opens bare domains as HTTPS.
- Treats unknown phrases as a search query.

The default search provider for the first implementation is DuckDuckGo because it avoids
hard-coding Google into a privacy-sensitive browser surface. The resolver should keep the
search URL configurable in code so product settings can later expose it.

### Workspace Content Selection

The selected content tab can be:

- A terminal tab from the focused terminal pane.
- A file workspace tab.
- A web workspace tab.

Selecting a web tab hides terminal search UI, clears file-manager keyboard focus, and does
not change terminal pane topology. Returning to terminal content should focus the previous
terminal tab when possible.

### Top Tab Strip

Web tabs appear in the same top content tab section as file tabs, after a divider from
workspace tabs. A web tab row shows:

- Globe or favicon.
- Page title or host.
- Loading indicator.
- Close button.
- Middle-truncated title for long URLs/titles.

Closing the selected web tab selects the nearest remaining web tab, then the last file tab,
then terminal content. Closing a background web tab preserves the current selection.

### Browser Surface

The browser surface has a compact toolbar:

- Back.
- Forward.
- Reload/Stop toggle.
- Address/search field.
- Progress indicator.
- Open externally.

The toolbar is intentionally in the workspace content area, not the global Conductor
toolbar. This keeps web controls contextual and prevents terminal workflows from paying for
web UI state.

### New Windows and Popups

`target=_blank` and JavaScript window-open requests open as a new Conductor web tab when
WebKit provides a URL. If WebKit asks for a web view with no URL yet, the first
implementation opens the eventual request externally and records a compact tab error if
the external open fails. Conductor does not attach orphan popup `WKWebView` instances in
the first implementation.

### Downloads

Downloads should use `WKDownloadDelegate` when available. The default destination is
`~/Downloads`, preserving the suggested filename. If a destination cannot be resolved, the
download is cancelled and the tab receives a compact error state. A later settings pass can
make this configurable.

### Errors

Navigation failures produce a bounded metadata error:

- Failed URL.
- User-visible localized message.
- Recoverable action: reload or edit address.

Do not store page HTML, response bodies, or long network logs in SwiftUI state.

### Privacy and State

Initial implementation uses `WKWebsiteDataStore.default()` so users stay logged in across
app launches, matching developer preview workflows. Web browsing history is not persisted
in Conductor's own model. Only compact tab metadata is persisted:

- Tab ID.
- Last URL.
- Title.
- Pending address text.
- Loading flags are not persisted.

The first implementation restores compact web-tab metadata. A future settings pass can
choose between restore web tabs, open blanks, or close web tabs on launch.

## Architecture

### Model Layer

Add a small pure model in `ConductorCore`:

- `WebTabID`
- `WorkspaceWebTabState`
- `WebAddressResolver`
- `WorkspaceWebTabList` for append/select/close/update behavior

This keeps URL resolution and tab selection rules testable without SwiftUI/WebKit.

`ConductorWindowModel` owns published web-tab state for the app shell and delegates pure
transformations to the model helpers. It should not store `WKWebView`, `WKNavigation`, page
HTML, or browser-process state.

### UI Layer

Add a focused web feature folder:

```text
Apps/Conductor/Sources/Conductor/UI/Web/
  ConductorWebWorkspaceView.swift
  ConductorWebSurfaceRepresentable.swift
  ConductorWebSnapshot.swift
  ConductorWebCommands.swift
```

`ConductorWebWorkspaceView` draws the contextual toolbar, blank page, error view, and hosts
the representable.

`ConductorWebSurfaceRepresentable` is the smallest AppKit bridge. It owns `WKWebView`, its
configuration, navigation delegate, UI delegate, download delegate, and KVO tokens. It emits
compact events back to `ConductorWindowModel`.

`ConductorWebSnapshot` is an immutable value built from the window model so leaf views do
not observe the entire model unnecessarily.

### AppKit Boundary

Use `NSViewRepresentable` for the web surface. SwiftUI creates layout and command chrome.
The representable owns:

- `WKWebView`.
- `WKNavigationDelegate`.
- `WKUIDelegate`.
- `WKDownloadDelegate`.
- KVO for URL, title, estimated progress, loading, back/forward availability.

The bridge emits events:

- `didStartLoading(tabID, url)`
- `didCommitURL(tabID, url)`
- `didUpdateTitle(tabID, title)`
- `didUpdateProgress(tabID, progress)`
- `didFinish(tabID)`
- `didFail(tabID, url, message)`
- `didRequestNewTab(url)`
- `didStartDownload(tabID, suggestedFilename)`
- `didFinishDownload(tabID, destinationURL)`

The bridge must not become a second app model. It only adapts WebKit events.

### Command Routing

Add shell commands:

- `newWebTab`
- `openWebLocation`
- `closeSelectedWebTab` if the selected content tab is web

Existing close-selected behavior should close file/web content first when selected, then
fall back to terminal tab close. This matches the visible content tab model.

### Persistence

`WorkspacePersistence` already persists workspace and appearance. Web tabs should be added
to the persisted payload only as compact Codable records. Migration must tolerate old state
files that do not have web tabs.

### Licensing

The implementation will be original Conductor code unless a specific Apache-2.0 snippet is
copied from DuckDuckGo. If any such snippet is copied:

- Preserve the original copyright/license header in that file or adjacent notice.
- Add a modified-file note.
- Add/update third-party notices if the repo has a notice file.
- Do not copy DuckDuckGo proprietary fonts/assets.

GPL code from Ora or Nook will not be copied.

## Testing

### Pure Model Checks

Add checks to `ConductorModelCheck` for:

- Address resolver direct HTTP/HTTPS URL behavior.
- Localhost and loopback URL behavior.
- Bare domain HTTPS behavior.
- Search-query fallback.
- Web tab append/select/update/close behavior.
- Close-selection fallbacks from selected web tab to web/file/terminal.

### Build Checks

Run:

```bash
swift run ConductorModelCheck
swift build
```

### Smoke Automation

Add a small web-tab smoke route that does not rely on external network:

- Open a blank web tab.
- Resolve a bundled local HTML URL through the model route.
- Confirm metadata updates and no terminal surfaces are recreated.
- If WebKit view loading is unavailable in the smoke environment, assert the model/UI state
  transitions and keep actual page rendering in the manual pass.

### Manual Validation

Manual pass:

- New web tab opens and address field focuses.
- `localhost:3000`, `github.com`, and a search phrase resolve correctly.
- Back/forward/reload/stop controls track WebKit state.
- A link with `target=_blank` opens in a new Conductor web tab or external fallback.
- Downloads go to `~/Downloads`.
- Switching terminal/file/web tabs does not recreate terminal surfaces.
- Closing selected and background web tabs chooses the expected next selection.

## Risks

- `WKWebView` is expensive. Keep one live web view per open web tab only when selected or
  deliberately retained. If memory use becomes high, add unloaded web tab state like
  DuckDuckGo's unloaded tabs.
- Full-screen video and WebKit inspector can have AppKit lifecycle traps. First
  implementation should avoid private API and accept limited behavior.
- Download delegate APIs vary by macOS version. Conductor targets macOS 14, so code must
  compile cleanly there.
- Web content can steal focus and shortcuts. The custom `ConductorWindow` shortcut routing
  must let text editing inside web pages work while preserving app shortcuts.
- Persisted web tabs might surprise users. Keep only compact URL/title state and make
  migration tolerant.

## Success Criteria

- Web tabs feel like first-class Conductor content tabs.
- The implementation remains native SwiftUI/AppKit/WebKit, not Electron.
- Terminal surface count stays stable through web tab operations.
- Pure behavior is covered by model checks.
- The code compiles on the project's SwiftPM/macOS 14 target.
- Any borrowed open-source code is license-compatible and attributed.
