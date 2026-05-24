# Web Tabs Design

## Goal

Add a lightweight web tab to Conductor so users can open websites, local dev servers, documentation, and web tools inside the same workspace where they already use terminals and files.

This is not a full browser. The first version should feel like a focused developer web workspace: fast to open, visually quiet, and integrated with the existing tab model.

## User Experience

Web tabs live beside file tabs in the current workspace content tab strip. A workspace can therefore contain terminal panes, opened files, and opened web pages without forcing users into a separate browser-like mode.

Creating a web tab opens a refined new-tab surface. The surface has a focused address input and a small set of useful entries such as local dev server shortcuts, GitHub, documentation, and recent web pages. It should avoid large marketing-style cards and avoid visual clutter.

After navigation, the web tab shows a thin page toolbar at the top of the tab content. The toolbar contains:

- Back
- Forward
- Reload or stop
- Address/search field
- Open externally

The toolbar appears only inside web tabs. It must not change terminal, file, or overview chrome.

## Address Behavior

The address field accepts both URLs and searches.

- `https://example.com` opens directly.
- `example.com` opens as `https://example.com`.
- `localhost:3000` and `127.0.0.1:5173` open as HTTP local development URLs.
- Plain text opens with the configured default search provider.

The first version can use a fixed default search provider if the app does not yet have a search engine preference.

## Architecture

Add a new workspace content tab type for web pages, parallel to existing file content tabs.

Suggested model shape:

- `ConductorWorkspaceWebTab`: id, title, currentURL, pendingInput, loading state, navigation capability state, and optional faviconURL for future favicon display.
- `ConductorWorkspaceContentTabID`: add a web case beside file cases.
- `ConductorWindowModel`: owns web tab creation, selection, closing, title updates, and URL submission.
- `ConductorWebWorkspaceView`: SwiftUI shell for the web tab toolbar and web content.
- `ConductorWebView`: AppKit/WebKit bridge wrapping `WKWebView`.

The WebKit view should be isolated from the rest of the shell. Navigation callbacks update only the web tab model. The terminal and file systems should not depend on web-specific state.

## Performance Rules

Performance is the priority.

- Do not render hidden web tabs eagerly.
- Keep inactive web tabs lightweight; only the selected web tab should host an active `WKWebView` in the first version.
- Do not add large page previews to overview in version one.
- Avoid polling. Use `WKNavigationDelegate` and KVO-style state updates for loading/title/canGoBack/canGoForward.
- Do not inject heavy JavaScript unless required for a specific later feature.

If preserving full web process state for inactive tabs becomes necessary later, design it as an explicit second phase after measuring memory and responsiveness.

## Visual Design

The web tab should feel native to Conductor, not like an AI-generated dashboard.

The new-tab surface should be sparse: one high-quality input, compact recent items, and restrained local-service shortcuts. Use the existing Conductor theme, typography, icon buttons, hover treatment, and animation timing.

Toolbar controls should use icon buttons with tooltips. The URL field should be stable in height and should not cause layout shift when the URL changes. Loading state should be subtle: a small progress indicator or reload/stop icon swap is enough.

## Error Handling

For invalid input, keep focus in the address field and show a restrained inline error.

For network failures, show a lightweight error surface inside the web tab with:

- Failed URL
- Retry
- Open externally

For local dev server failures, the message should be short and practical, for example: "Cannot reach localhost:3000".

## Commands

Add command entries after the core tab works:

- New Web Tab
- Open URL
- Reload Web Tab
- Open Current Page Externally

Keyboard shortcuts should be chosen carefully so they do not conflict with terminal workflows.

## Out Of Scope For Version One

- Downloads
- Browser history manager
- Bookmarks manager
- Password handling
- Extensions
- Developer tools integration
- Multi-profile browsing
- Permission management beyond the default WebKit behavior

## Test Plan

Manual verification:

- Create a web tab and confirm the address field is focused.
- Open `localhost:3000`, `github.com`, and a normal search query.
- Confirm back, forward, reload, and open externally work.
- Switch between terminal, file, and web tabs without focus confusion.
- Confirm file panel and other overlays do not visually collide with the web toolbar.
- Confirm hidden web tabs are not rendered in bulk.

Automated or model checks:

- URL parsing tests for direct URLs, domain-like input, localhost input, and search text.
- Model tests for create/select/close web tabs.
- Build check for the app product.
