# Project-wide Performance and Interaction Audit

## Goal

Run a whole-project audit of Conductor's performance, responsiveness, and human interaction quality, then produce an exhaustive, actionable issue list. The audit must be detailed enough to catch low-level feel problems such as cursor ownership, first-responder handoff, hover persistence, live-resize jank, animation mismatch, input latency, scroll behavior, visual density, and missing affordances.

## What I Already Know

- The app is a high-performance native macOS multi-terminal manager.
- Terminal rendering must stay owned by GhosttyKit/AppKit; SwiftUI should only observe compact metadata.
- Recent fixes exposed several classes of problems:
  - right-side file manager width animation caused terminal split resize jank;
  - SwiftUI `TextEditor` made text/log editing slow during resize;
  - search fields could lose cursor/focus because terminal focus restoration was too aggressive;
  - hover tooltip state could remain visible after the pointer left;
  - Markdown/document preview chrome and outline navigation had plain-mode and scroll-target issues;
  - sidebar visual details such as top fade masks can read as accidental shadows.
- The source inventory currently contains 51 app/core/check files, including bundled document viewer vendor assets. The baseline file list is recorded at `research/source-file-inventory.txt`.

## Requirements

- Cover every source file in `Apps/Conductor/Sources`, including Swift files and bundled document viewer JS/CSS resources.
- For each file, record an audit status: reviewed, third-party/vendor bounded review, or intentionally skipped with reason.
- Find performance risks:
  - main-thread IO or parsing;
  - SwiftUI state tied to high-frequency terminal/runtime data;
  - expensive `body` computation;
  - repeated layout, animation, or AppKit view replacement;
  - unbounded text/image/document loading;
  - live-resize, split-drag, or tray-opening jank;
  - unnecessary rebuilds caused by broad `@ObservedObject` subscriptions.
- Find interaction and feel risks:
  - cursor shape and cursor rectangle mismatches;
  - first-responder/focus theft;
  - keyboard shortcut capture in the wrong mode;
  - hover/tooltip/menu state persistence;
  - search field caret and selection behavior;
  - scroll positioning, outline jumps, and selection visibility;
  - drag/drop affordances and error recovery;
  - animation timing mismatch, disjoint motion, or motion that changes expensive layout;
  - insufficient metadata, missing empty states, unclear disabled states, and low-signal labels.
- Prioritize issues by product impact:
  - P0: can freeze/hang/crash or corrupt user work;
  - P1: visible jank, focus/cursor breakage, lost input, or major workflow friction;
  - P2: recurring polish/usability issue that makes the app feel unreliable;
  - P3: cleanup, consistency, or low-risk visual refinement.
- Produce a follow-up implementation roadmap grouped by fix batch, where each batch has a small blast radius and verification checklist.

## Acceptance Criteria

- [ ] A coverage matrix exists and accounts for every file from `research/source-file-inventory.txt`.
- [ ] Each audited file has concrete notes or a reason why only bounded/vendor review was done.
- [ ] Findings include file paths, affected workflow, severity, likely root cause, and proposed fix direction.
- [ ] The audit explicitly covers cursor/focus behavior, search behavior, hover/tooltip behavior, animation/layout, resize, scrolling, file/document surfaces, terminal surfaces, settings panels, file manager, workspace/sidebar, notifications, command palette, and persistence.
- [ ] The audit distinguishes measured/verified problems from inferred risks.
- [ ] Recommended fixes are grouped into sequenced batches with validation steps.

## Out of Scope

- Implementing all fixes inside the audit task.
- Replacing GhosttyKit/libghostty rendering.
- Rewriting the whole UI architecture in one pass.
- Deep security review of third-party minified vendor libraries beyond performance/use-fit and integration risks.

## Technical Notes

- Primary code roots:
  - `Apps/Conductor/Sources/Conductor`
  - `Apps/Conductor/Sources/ConductorCore`
  - `Apps/Conductor/Sources/ConductorModelCheck`
- Primary specs:
  - `.trellis/spec/guides/high-performance-terminal-roadmap.md`
  - `.trellis/spec/frontend/component-guidelines.md`
  - `.trellis/spec/frontend/state-management.md`
  - `.trellis/spec/frontend/motion-language.md`
  - `.trellis/spec/frontend/quality-guidelines.md`
  - `.trellis/spec/backend/ghosttykit-integration.md`
  - `.trellis/spec/backend/quality-guidelines.md`
- Audit output should live under this task's `research/` directory before implementation tasks are split out.
