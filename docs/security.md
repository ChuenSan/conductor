# Security Model

Conductor's updater is designed to avoid replacing the running app in-process.

## Defaults

- Updates are read from a configured manifest URL.
- Downloaded packages must match the manifest SHA-256.
- The staged app must match the expected bundle identifier.
- The staged app must pass `codesign --verify --deep --strict`.
- Replacement is performed by an external script after Conductor exits.

## Private Repository Policy

The GitHub repository is private and should keep write access limited to the owner account. The default branch is `main`.

## Notes

The current scripts support ad-hoc signing for local builds. Production distribution should use a Developer ID Application identity and notarization before a public release.
