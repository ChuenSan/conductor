# Frontend Development Guidelines

> Native macOS UI guidelines for this project.

---

## Overview

In this project, "frontend" means the native macOS application shell: SwiftUI views, AppKit bridges, workspace chrome, tabs, split panes, notification UI, command palette, settings, and browser/tool pane chrome. It does not mean a web frontend.

Before UI work, read [High Performance Terminal Roadmap](../guides/high-performance-terminal-roadmap.md).

---

## Guidelines Index

| Guide | Description | Status |
|-------|-------------|--------|
| [Directory Structure](./directory-structure.md) | Module organization and file layout | To fill |
| [Component Guidelines](./component-guidelines.md) | SwiftUI/AppKit component boundaries | Filled: initial route |
| [Hook Guidelines](./hook-guidelines.md) | Custom hooks, data fetching patterns | To fill |
| [Motion Language](./motion-language.md) | Product motion map and interaction animation contracts | Filled: initial motion contract |
| [State Management](./state-management.md) | State boundaries for high-frequency terminal data | Filled: initial route |
| [Quality Guidelines](./quality-guidelines.md) | UI performance and review standards | Filled: initial route |
| [Type Safety](./type-safety.md) | Type patterns, validation | To fill |

---

## How to Fill These Guidelines

For each guideline file:

1. Document your project's **actual conventions** (not ideals)
2. Include **code examples** from your codebase
3. List **forbidden patterns** and why
4. Add **common mistakes** your team has made

The goal is to help AI assistants and new team members understand how YOUR project works.

---

**Language**: All documentation should be written in **English**.
