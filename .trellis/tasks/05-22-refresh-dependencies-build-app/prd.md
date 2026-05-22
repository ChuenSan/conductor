# Refresh Dependencies And Build App Bundle

## Goal

Refresh Conductor's local build dependencies and produce a fresh macOS app bundle from the current `main` branch.

## Requirements

- Re-resolve Swift Package Manager dependencies from the current `Package.swift`.
- Re-prepare the GhosttyKit binary dependency.
- Build a new `Conductor.app` bundle.
- Do not commit or modify unrelated local IDE state.

## Acceptance Criteria

- [ ] Dependency refresh completes without errors.
- [ ] `Apps/Conductor/.build/Conductor.app` exists after the build.
- [ ] Report the final app path and any remaining local dirty files.

## Technical Notes

- Build script: `Apps/Conductor/Scripts/build-app-bundle.sh`.
- GhosttyKit script: `Apps/Conductor/Scripts/prepare-ghosttykit.sh`.
