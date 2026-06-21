# Conductor Command Deck Design

Date: 2026-06-21

## Purpose

Conductor has accumulated strong individual capabilities: real terminals, workspaces, panes, AI sessions, task cards, Hooks, MCP, Skills, usage monitoring, notifications, companion status, onboarding, and settings. The product problem is that these capabilities currently feel like separate additions rather than one coherent application.

This design establishes a product model for Conductor as an AI command deck. It is intended to guide future UI and interaction changes before more feature work is added.

## Product Thesis

Conductor is a command deck for directing AI work.

The user should feel that they are running a coordinated workspace, not managing a pile of tools. Every feature must answer one question:

Where does this belong in the command deck?

## World Model

The product uses a conductor metaphor, but the UI should remain clean and work-focused. The metaphor defines structure, not decorative language.

- Workspace: the stage for one project.
- Pane: one active voice in the project.
- Agent: a performer attached to a pane or session.
- Task card: a score fragment that can be assigned to a pane or agent.
- Session: the record of previous agent work.
- Hooks, MCP, Skills, and CLI tools: the capability library.
- Companion and notifications: the attention layer that tells the user who needs direction.
- Settings: the backstage system for global preferences.

The user should not have to learn a different model for every module. Work should move through the same loop everywhere:

1. Choose a project workspace.
2. Start or resume voices.
3. Assign tasks or prompts.
4. Watch progress and attention signals.
5. Review output.
6. Reuse or restore context.

## Layer Rules

Every visible command belongs to exactly one layer.

### Global Layer

Global commands affect the whole app or command deck.

Examples:
- Settings.
- Theme.
- Updates.
- Tool and capability management.
- App-wide command palette.

Allowed surfaces:
- Top global toolbar.
- Command palette.
- Settings window.
- Application menu.

Not allowed:
- Global settings inside pane controls.
- App-wide tool configuration inside individual workspace rows.

### Workspace Layer

Workspace commands affect a project stage.

Examples:
- Add, remove, rename, reorder workspaces.
- Show workspace sessions.
- Save and restore layouts.
- Locate current folder.
- Reauthorize workspace directory.

Allowed surfaces:
- Sidebar workspace row.
- Workspace context menu.
- Workspace-specific session sections.
- Command palette entries scoped to workspaces.

Not allowed:
- Workspace management in the pane header.
- Workspace-only commands in the global toolbar unless they represent a global create action.

### Pane Layer

Pane commands affect one terminal voice.

Examples:
- Focus.
- Split right or down.
- Zoom or restore.
- Close.
- Search.
- Command log.
- Copy, paste, clear, select all.
- Copy cwd or reveal in Finder for the pane.

Allowed surfaces:
- Pane header.
- Pane context menu.
- Keyboard shortcuts.

Not allowed:
- App settings in pane controls.
- Capability installation in pane controls.
- Session management that is not scoped to the pane or its cwd.

### Agent Layer

Agent commands affect a performer attached to a workspace, pane, or session.

Examples:
- Launch an agent in a workspace.
- Resume a session.
- Ask for a second opinion.
- Show active, waiting, done, or approval state.
- Jump to the pane that needs attention.

Allowed surfaces:
- New tab hover menu.
- Pane context menu.
- Workspace session list.
- Companion or attention layer.
- Session manager.

Not allowed:
- Agent actions presented as generic app settings.
- Session actions that do not reveal their workspace or pane scope.

### Capability Layer

Capability commands manage what the deck can do.

Examples:
- CLI detection.
- MCP server enable, disable, edit.
- Hooks install and automation.
- Skills library, install, sync.
- Provider usage and credentials.

Allowed surfaces:
- A single Capability Library surface.
- Settings only for durable preferences, credentials, and policy.
- Command palette shortcuts into specific capability modules.

Not allowed:
- Separate top-level panels that feel unrelated.
- Capability actions mixed into workspace rows unless the action is scoped to that workspace.

### Task Layer

Task commands assign reusable work to a voice or agent.

Examples:
- Open task cards.
- Drag a task card to a pane.
- Fill variables.
- Run the task in shell or agent.

Allowed surfaces:
- Task card panel.
- Pane drop targets.
- Workspace-scoped task filters.
- Command palette.

Not allowed:
- Task cards as a detached feature with no connection to panes or agents.

## Navigation Structure

The main window should keep one stable mental model:

- Left: workspaces and project context.
- Center: panes and active work.
- Top: global deck controls and tabs.
- Pane header: local voice controls.
- Right or floating surfaces: temporary inspectors, capability library, session manager, task cards.
- Bottom: status, usage, and current path feedback.

The top toolbar should remain small. It is not a dumping ground. It should expose only deck-level entry points:

- Update status.
- Theme.
- Capability Library.
- Task Cards.
- Settings.

Everything else must be reachable through command palette, context menus, or the correct layer-specific surface.

## Interaction Language

The product should use the same interaction grammar everywhere.

### Click

Click selects or opens. It should not trigger hidden destructive or multi-step behavior.

Examples:
- Click workspace selects it.
- Click tab selects it.
- Click pane focuses it.
- Click global toolbar icon opens the relevant global surface.

### Double Click

Double click is reserved for a secondary direct manipulation action.

Examples:
- Double click tab title to rename.
- Double click pane header to zoom or restore.

### Drag

Drag means moving or assigning.

Examples:
- Drag workspace row to reorder workspaces.
- Drag pane header to rearrange panes.
- Drag task card to assign it to a pane.

Drag must show a visible drop result before release. If the action is not spatial or assignment-based, it should not be drag-only.

### Hover

Hover reveals secondary local controls. It should not be required for primary workflow discovery.

Examples:
- Pane controls can become more visible on hover.
- Workspace reorder handle can become more visible on hover.
- Session row hover can preview a transcript.

### Right Click

Right click reveals scoped power actions. Menus must stay within the layer of the thing that was clicked.

Examples:
- Workspace menu contains workspace commands.
- Pane menu contains pane and pane-scoped agent/session commands.
- Session menu contains resume, copy id, delete, and manage session commands.

### Command Palette

The command palette is the universal escape hatch. It should index all major commands, but it should not replace good placement in the UI.

Every command should have a scope label: Global, Workspace, Pane, Agent, Capability, or Task.

## Visual Language

The UI should feel like a quiet professional control surface.

Principles:
- Fewer top-level objects.
- Clear layer separation.
- Controls only become visually strong when they are active, hovered, selected, or urgent.
- Cards are for repeated items or true framed tools, not page sections.
- Pane-local chrome should look attached to the pane, not like another global toolbar.
- Global chrome can use a compact capsule, but it must remain grouped by intent.
- Accent color is a signal, not decoration.
- Status colors are reserved for state: done, warning, error, active.

Avoid:
- Adding a new floating panel for every feature.
- Repeating the same command in several unrelated places.
- Equal visual weight for global and local controls.
- Large illustrative surfaces inside operational tools.

## Information Architecture Changes

### Capability Library

The current Tools, Hooks, MCP, Skills, providers, and CLI detection surfaces should be grouped under one Capability Library concept.

Recommended sections:
- Overview.
- CLI Tools.
- Skills.
- MCP.
- Hooks.
- Providers and Usage.
- Activity.

Settings should keep durable preferences. Capability Library should keep operational management.

### Session And Agent Work

Sessions should be treated as work records tied to workspaces and panes.

Recommended behavior:
- Workspace rows show recent sessions scoped to that workspace.
- Pane context menu shows sessions scoped to the pane cwd.
- Session manager remains the full archive and search surface.
- Companion highlights active or attention-needed agent work and can jump to the relevant pane.

### Task Cards

Task cards should be positioned as assignable work.

Recommended behavior:
- Opening the task panel shows reusable cards.
- Dragging a card to a pane is the primary spatial action.
- Cards can declare shell or agent execution.
- Variable fill appears only when needed.
- Recent cards can be suggested from workspace context.

### Onboarding

Onboarding should teach the command deck model, not enumerate features.

Recommended pages:
- Choose a project stage.
- Start voices.
- Assign work.
- Watch agents.
- Build capabilities.

## First Implementation Phase

The first phase should reorganize surfaces without changing core terminal or agent behavior.

Scope:
- Define command scope labels in code for major app commands.
- Rename and reshape the Tools entry into Capability Library.
- Make the top toolbar follow the Global Layer rule.
- Make pane controls follow the Pane Layer rule.
- Audit right-click menus for layer leaks.
- Update onboarding copy and screenshots to teach the command deck loop.
- Add tests for command classification and top-level surface grouping.

Out of scope:
- Rewriting terminal rendering.
- Replacing Ghostty integration.
- Rebuilding the full settings system.
- Adding new agents.
- Adding new task-card capabilities.
- Large visual rebrand beyond structural cleanup.

## Acceptance Criteria

The design is successful when:

- A new user can explain what a workspace, pane, agent, task card, and capability are after onboarding.
- Top toolbar actions are all global.
- Pane header actions are all pane-local.
- Workspace row actions are all workspace-local.
- Hooks, MCP, Skills, provider settings, and CLI detection live under one capability concept.
- Task cards feel assignable to panes rather than detached.
- Session surfaces always reveal their workspace or pane scope.
- New features can be placed by applying the layer rules without inventing a new top-level surface.

## Testing Strategy

Add lightweight model and presentation tests before UI changes:

- Command scope classification tests.
- Global toolbar grouping tests.
- Pane header action list tests.
- Workspace context action tests.
- Capability Library section ordering tests.
- Onboarding page model tests.

Use screenshot/manual review for final visual checks because several surfaces are SwiftUI/AppKit hybrids and Metal-backed terminal panes are not well covered by snapshot tests.

## Phase One Product Decisions

These choices are selected for the first implementation phase:

- Use "能力库" in Chinese and "Capability Library" in English.
- Reuse the current Tools panel as the first Capability Library shell instead of creating a new top-level window.
- Keep task cards floating in phase one, but make their assignment role explicit.
- Keep companion optional, but define it as the attention layer when enabled.
