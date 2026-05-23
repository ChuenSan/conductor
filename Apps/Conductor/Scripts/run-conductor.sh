#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

if [[ -x /usr/local/opt/swift/bin/swift ]]; then
  export PATH="/usr/local/opt/swift/bin:$PATH"
fi

APP="$(./Scripts/build-app-bundle.sh)"
EXECUTABLE="$APP/Contents/MacOS/Conductor"

if [[ ! -x "$EXECUTABLE" ]]; then
  echo "Conductor app executable not found at $EXECUTABLE" >&2
  exit 1
fi

open -n "$APP"
