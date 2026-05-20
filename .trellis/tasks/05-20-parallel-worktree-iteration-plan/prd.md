# brainstorm: parallel worktree iteration plan

## Goal

Plan a fast, parallel iteration system for Conductor using the current validated Intel package as the product baseline. The goal is to let multiple worktrees move independently while preserving stability, native macOS feel, terminal rendering boundaries, and a clear merge/release path.

## What I already know

* The project is a native macOS multi-terminal manager using SwiftUI shell, AppKit integration, and GhosttyKit/libghostty rendering.
* The current local version passed `swift build`, `ConductorModelCheck`, and `./Scripts/check-conductor.sh`.
* A fresh Intel package exists at `Apps/Conductor/dist/Conductor-Intel.zip`.
* The current branch is `main`, ahead of `origin/main` by 22 commits.
* The worktree still has uncommitted changes and untracked generated/task files.

## Assumptions (temporary)

* The current validated build should become the baseline before parallel work starts.
* Parallel worktrees should be split by ownership boundary, not by arbitrary file count.
* Every worktree should be independently buildable and mergeable back into an integration branch.
* High-frequency terminal output must stay out of SwiftUI state in every workstream.

## Open Questions

* Do we freeze the current validated build as a tagged baseline before creating all parallel worktrees?

## Requirements (evolving)

* Define a baseline, branching, and worktree naming convention.
* Split work into independent product tracks with clear file ownership.
* Define per-worktree quality gates.
* Define merge order and conflict policy.
* Define daily package/release rhythm.

## Acceptance Criteria (evolving)

* [ ] Baseline commit/tag is selected.
* [ ] Worktree matrix is defined with owner, branch, scope, and gate.
* [ ] Integration branch and merge queue rules are defined.
* [ ] Regression checklist maps to current scripts and manual smoke checks.
* [ ] Rollback rule is defined for broken worktrees.

## Definition of Done

* Tests added/updated where behavior changes.
* `swift build`, `ConductorModelCheck`, and relevant automation pass per worktree.
* Full `./Scripts/check-conductor.sh` passes before integration/release.
* Docs/notes updated when behavior or conventions change.
* Rollout/rollback considered for risky workstreams.

## Out of Scope

* Replacing GhosttyKit/libghostty rendering.
* Moving terminal scrollback into SwiftUI.
* Starting a cloud/backend product surface.

## Technical Notes

* Current dirty status includes app UI files, motion docs, watchdog, and generated package output.
* Existing package script: `Apps/Conductor/Scripts/build-app-bundle.sh`.
* Existing full gate: `Apps/Conductor/Scripts/check-conductor.sh`.
* Existing Intel package path: `Apps/Conductor/dist/Conductor-Intel.zip`.
