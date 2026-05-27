# Getting Started

Conductor is a SwiftPM-based macOS app. The production app lives in `Apps/Conductor`.

## Requirements

- macOS 14 or newer
- Xcode Command Line Tools
- Swift 6 toolchain

## First Run

```bash
cd Apps/Conductor
./Scripts/prepare-ghosttykit.sh
swift build
swift run ConductorModelCheck
./Scripts/run-conductor.sh
```

## App Bundle

```bash
cd Apps/Conductor
./Scripts/build-app-bundle.sh
open .build/Conductor.app
```

## Local State

Window layout and appearance are persisted under:

```text
~/Library/Application Support/Conductor/window-state.json
```

Useful validation flags:

```bash
CONDUCTOR_RESET_STATE=1 ./Scripts/run-conductor.sh
CONDUCTOR_DISABLE_PERSISTENCE=1 ./Scripts/run-conductor.sh
```
