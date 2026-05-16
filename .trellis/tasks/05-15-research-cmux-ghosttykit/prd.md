# Research cmux GhosttyKit Integration

## Goal

Study cmux's code in detail to understand how it uses Ghostty/libghostty without embedding the standalone Ghostty app. Capture the integration route for this project, whose product UI must remain custom SwiftUI/AppKit.

## Questions

- How does cmux link and initialize GhosttyKit?
- What does cmux own versus what does Ghostty own?
- How are surfaces created, attached, resized, focused, and freed?
- How are keyboard, mouse, scroll, paste, and automation input sent to Ghostty?
- Which parts can be replaced with custom UI, and which parts are effectively part of Ghostty's renderer?
- When would we need to fall back to the cmux-style portal approach?

## Deliverables

- A research note under `research/`.
- A durable spec under `.trellis/spec/backend/` for future implementation.

## Current Direction

We are not embedding Ghostty.app. We are building a custom macOS terminal manager UI. For the first validation and MVP, the live terminal character surface should be GhosttyKit's Metal-backed NSView while we customize everything around it. A deeper custom renderer using Ghostty VT/render-state internals is deferred until the surface route is proven insufficient.
