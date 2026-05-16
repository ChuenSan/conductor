# Logging Guidelines

> How runtime diagnostics are done in this project.

---

## Overview

Logging should make terminal lifecycle and performance issues diagnosable without recording user transcript content.

---

## Log Levels

- Debug: lifecycle transitions, resize dedup decisions, focus routing, portal binding, throttling/coalescing counters.
- Info: app startup, Ghostty runtime initialization, workspace/session creation, automation command acceptance.
- Warn: recoverable failed surface creation, stale callback ignored, missing display id, slow metadata probe, dropped over-limit queue.
- Error: unrecoverable Ghostty initialization failure, surface creation failure after fallback, automation protocol violation, persistent main-thread stall.

---

## Structured Logging

Prefer structured logs or signposts with these fields when relevant:

- `workspaceId`
- `surfaceId`
- `paneId`
- `windowId`
- `event`
- `durationMs`
- `queueDepth`
- `bytes`
- `reason`

Use stable IDs, not transcript content.

---

## What to Log

Log:

- Ghostty app init and config fallback.
- Surface create/free/attach/detach/reattach.
- Display id, content scale, and pixel size changes.
- Focus transitions and rejected focus attempts.
- Portal bind/rebind/release.
- High-frequency event coalescing and dropped input/output queues.
- Agent notification arrival, read/dismiss state, and jump-to-unread target.
- Automation socket command start/end and failure reason.

---

## What NOT to Log

Never log:

- Full terminal transcript or prompt content.
- Environment variable values that may contain secrets.
- API keys, tokens, cookies, SSH details, private file contents.
- Browser page content unless the user explicitly requests debug capture.
