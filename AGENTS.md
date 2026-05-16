<!-- TRELLIS:START -->
# Trellis Instructions

These instructions are for AI assistants working in this project.

This project is managed by Trellis. The working knowledge you need lives under `.trellis/`:

- `.trellis/workflow.md` — development phases, when to create tasks, skill routing
- `.trellis/spec/` — package- and layer-scoped coding guidelines (read before writing code in a given layer)
- `.trellis/workspace/` — per-developer journals and session traces
- `.trellis/tasks/` — active and archived tasks (PRDs, research, jsonl context)

If a Trellis command is available on your platform (e.g. `/trellis:finish-work`, `/trellis:continue`), prefer it over manual steps. Not every platform exposes every command.

If you're using Codex or another agent-capable tool, additional project-scoped helpers may live in:
- `.agents/skills/` — reusable Trellis skills
- `.codex/agents/` — optional custom subagents

Managed by Trellis. Edits outside this block are preserved; edits inside may be overwritten by a future `trellis update`.

<!-- TRELLIS:END -->

# Project Route

This project is a high-performance native macOS multi-terminal manager. The UI shell is SwiftUI-first, platform integration is AppKit-first, terminal semantics come from Ghostty/libghostty, and the initial terminal character surface is GhosttyKit/libghostty's macOS renderer hosted inside our UI.

Before working on terminal panes, split panes, workspace switching, notifications, agent status, or automation, read:

- `.trellis/spec/guides/high-performance-terminal-roadmap.md`
- `.trellis/spec/frontend/component-guidelines.md`
- `.trellis/spec/frontend/state-management.md`
- `.trellis/spec/backend/directory-structure.md`
- `.trellis/spec/backend/quality-guidelines.md`
- `.trellis/spec/backend/ghosttykit-integration.md`

The hard rule: terminal scrollback, transcript text, ANSI rendering, cursor movement, and high-frequency output must not enter SwiftUI state or per-cell SwiftUI rendering. SwiftUI owns compact app metadata and controls. For the first validation and MVP, GhosttyKit/libghostty owns the live terminal character renderer through a stable AppKit host view. A custom renderer driven by Ghostty VT/render-state APIs remains a future path if the Ghostty surface route blocks required product behavior.
