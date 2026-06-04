# Updating Conductor

Conductor uses GitHub Releases as the update source. Normal users should see simple app states such as **Update available**, **Downloading**, **Ready to install**, and **Failed**. Raw manifest URLs and release asset names belong in diagnostics or maintainer docs, not normal app UI.

## User Flow

1. Conductor checks for a newer release after launch, and then quietly checks again about once per hour when automatic checks are enabled. Repeated background failures back off up to about six hours and stay in diagnostics instead of interrupting the normal UI.
2. If a newer compatible build exists, the app shows a quiet update button or panel state.
3. The user starts the download.
4. The app shows progress.
5. The package is verified.
6. An external installer replaces the app after Conductor exits.
7. Conductor reopens.

## Expected UI States

- **Checking:** the app is asking GitHub Releases for update metadata.
- **Up to date:** no newer compatible build is available.
- **Update available:** a newer build exists.
- **Downloading:** package download is in progress.
- **Ready to install:** the package is downloaded and verified.
- **Installing:** the external installer is replacing the app.
- **Failed:** a human-readable failure occurred, with retry or open releases action.

## Safety Checks

Before replacement, Conductor should verify:

- downloaded package SHA-256 checksum
- expected bundle identifier
- code signing verification, including ad-hoc signatures for preview builds
- staged app exists and is readable
- app path is writable for replacement

## Public Preview Signing

Unless a release explicitly says it is Developer ID signed and notarized, Conductor preview builds may be ad-hoc signed.

That means macOS may ask for extra confirmation on first launch. This is expected for preview builds from an independent developer without paid Developer ID distribution.

## Maintainer Release Assets

A complete release should include:

- `Conductor-<version>-<build>-macos-arm64.zip`
- `Conductor-<version>-<build>-macos-x86_64.zip`
- `latest-stable-macos-arm64.json`
- `latest-stable-macos-x86_64.json`
- SHA-256 checksums
- release notes
- current screenshots

Optional:

- delta package from the previous build
- short demo video or GIF

## Package A Release

From `Apps/Conductor`:

```bash
CONDUCTOR_GITHUB_REPO=owner/repo \
./Scripts/package-release.sh 0.0.3 3
```

Publish generated assets:

```bash
CONDUCTOR_GITHUB_REPO=owner/repo \
./Scripts/publish-github-release.sh \
../../Artifacts/releases/0.0.3-3-macos-arm64 v0.0.3
```

For signed production builds:

```bash
CONDUCTOR_BUNDLE_IDENTIFIER=com.example.conductor \
CONDUCTOR_CODE_SIGN_IDENTITY="Developer ID Application: Example" \
CONDUCTOR_GITHUB_REPO=owner/repo \
./Scripts/package-release.sh 0.0.3 3
```

## Diagnostics

Update diagnostics should include:

- current app version and build
- selected update channel
- last check time
- last available version
- download state
- last error
- automatic-check next run, consecutive background failure count, and last background failure
- verification result
- install handoff state

Normal user UI should not show raw manifest URLs. Diagnostics may include them for maintainers.

## Maintainer Verification

Run the local update fixture before publishing a release candidate:

```bash
cd Apps/Conductor
./Scripts/update-fixture.sh
```

The fixture starts an isolated app with a temporary home directory, state file, control socket, manifest directory, current-app override, and update download directory. It verifies that a local newer manifest is detected, a delayed local package copy enters a visible downloading state, an in-flight cancel returns to an available retryable state, a later delayed download reports increasing progress samples through `update status`, the package downloads with a matching SHA-256, the installer can stage and verify a signed `.app` in dry-run mode, a deliberately tampered package reports a failed update before install, and the diagnostics performance gate records `update.check` samples within budget.

## Troubleshooting

### Update Button Does Not Appear

Possible causes:

- no newer compatible release exists
- app cannot reach GitHub
- the release is missing the current architecture asset
- the update channel is disabled or not configured

### Download Is Slow

Possible causes:

- GitHub asset download is slow
- network is throttled
- progress reporting is waiting for reliable byte counts

The update panel should show progress and allow retry/cancel when supported.

### Install Fails

Possible causes:

- checksum mismatch
- staged app has the wrong bundle identifier
- code signing verification failed
- Conductor is running from a read-only or unusual location
- external installer could not replace the app

See [Troubleshooting](troubleshooting.md) for user-facing recovery steps.
