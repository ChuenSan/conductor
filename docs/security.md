# Security Model

Conductor is a local macOS workbench. Its security model is built around local-only control, local state, explicit update verification, and honest preview-build signing limits.

## Local Control API

Conductor exposes a Unix domain socket while the app is running:

```text
~/Library/Application Support/Conductor/control.sock
```

Properties:

- local to the current user
- no HTTP server
- no remote network listener
- request/response JSON only
- scriptable but not internet-exposed

For isolated tests, the socket path can be overridden:

```bash
CONDUCTOR_CONTROL_SOCKET_PATH=/tmp/conductor-control.sock
```

The control API can operate the app, so do not share access to your user account with untrusted scripts.

## Local State

Conductor stores app state under:

```text
~/Library/Application Support/Conductor/
```

Important files:

- `window-state.yaml`
- `attention-events.json`
- `control.sock` while running

Diagnostics and screenshots should be reviewed before sharing publicly. Local paths, email addresses, project names, terminal output, and usage/account data can appear in app state or screenshots.

## Browser And Credentials

Normal browser snapshots should not expose cookies, passwords, or token data. Any future advanced browser storage/cookie commands must be explicit and documented separately.

## Updater Safety

Conductor's updater avoids replacing the running app in-process. It stages a downloaded app, verifies it, then hands replacement to an external installer after Conductor exits.

Update safety checks should include:

- SHA-256 checksum from release metadata
- expected bundle identifier
- `codesign --verify --deep --strict`
- staged app path validation

Normal update UI should hide raw release internals. Diagnostics can include them for maintainers.

## Repository Policy

The GitHub repository can be public so release assets and update metadata are downloadable without authentication.

Recommended policy:

- protect `main`
- require pull requests for external contributors
- allow issues for bug reports and feature requests
- limit direct write access to the owner account
- use release assets for app distribution

## Signing And Gatekeeper

Preview releases may be ad-hoc signed unless the release says otherwise. Ad-hoc signing is useful for independent preview distribution, but it is not the same as Developer ID notarization.

What users may see:

- macOS blocks first launch
- macOS asks the user to confirm opening the app
- update replacement may require extra trust steps

For broad public distribution, Developer ID Application signing and notarization are recommended.

## Reporting Security Issues

If you find a security issue:

1. Do not post private tokens, local paths, or logs publicly.
2. Capture the app version, macOS version, and a short reproduction.
3. Attach diagnostics only after reviewing/redacting sensitive content.
