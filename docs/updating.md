# Updating Conductor

Conductor uses GitHub Releases as the update source.

## Release Assets

Each release can publish:

- full app bundle zip
- optional file-level delta zip
- `latest-stable-macos-arm64.json`

The app reads the latest manifest from:

```text
https://github.com/owner/repo/releases/latest/download/latest-stable-macos-arm64.json
```

## Build Artifacts

```bash
CONDUCTOR_GITHUB_REPO=owner/repo \
Apps/Conductor/Scripts/package-release.sh 2026052701
```

The script writes both local/static-hosting manifests and GitHub Release asset manifests.

## Publish

```bash
Apps/Conductor/Scripts/publish-github-release.sh \
Artifacts/releases/0.1.1-2026052701-macos-arm64
```

## Runtime Flow

1. App checks the stable latest manifest.
2. Version/build are compared with the current bundle.
3. Delta package is selected when available and enabled.
4. Downloaded zip is verified with SHA-256.
5. A short external installer script waits for the app to quit.
6. The installer verifies code signing, replaces the app, and reopens it.
