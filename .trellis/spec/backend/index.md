# Backend Development Guidelines

> Runtime and platform-layer guidelines for this project.

---

## Overview

In this project, "backend" means the native runtime layer: Ghostty/libghostty integration, PTY lifecycle, automation socket/API, metadata extraction, hooks, logging, persistence, and background work. It does not necessarily mean a web server.

Before runtime work, read [High Performance Terminal Roadmap](../guides/high-performance-terminal-roadmap.md).

---

## Guidelines Index

| Guide | Description | Status |
|-------|-------------|--------|
| [Directory Structure](./directory-structure.md) | Native app runtime module boundaries | Filled: initial route |
| [GhosttyKit Integration](./ghosttykit-integration.md) | How to use Ghostty/libghostty without embedding Ghostty.app | Filled: cmux research |
| [Database Guidelines](./database-guidelines.md) | ORM patterns, queries, migrations | To fill |
| [Error Handling](./error-handling.md) | Error types, handling strategies | To fill |
| [Quality Guidelines](./quality-guidelines.md) | Runtime performance and correctness standards | Filled: initial route |
| [Logging Guidelines](./logging-guidelines.md) | Runtime diagnostics and performance logging | Filled: initial route |

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
