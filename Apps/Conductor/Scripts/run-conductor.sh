#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

if [[ -x /usr/local/opt/swift/bin/swift ]]; then
  export PATH="/usr/local/opt/swift/bin:$PATH"
fi

./Scripts/prepare-ghosttykit.sh
CONFIGURATION="${CONDUCTOR_BUILD_CONFIGURATION:-release}"
case "$CONFIGURATION" in
  debug|release) ;;
  *)
    echo "Unsupported CONDUCTOR_BUILD_CONFIGURATION: $CONFIGURATION" >&2
    echo "Use 'debug' or 'release'." >&2
    exit 2
    ;;
esac
SWIFT_BUILD_ARGS=(-c "$CONFIGURATION")
if [[ "$CONFIGURATION" == "release" && "${CONDUCTOR_CROSS_MODULE_OPTIMIZATION:-1}" != "0" ]]; then
  SWIFT_BUILD_ARGS+=(-Xswiftc -cross-module-optimization)
fi
swift build "${SWIFT_BUILD_ARGS[@]}"
exec "$(swift build "${SWIFT_BUILD_ARGS[@]}" --show-bin-path)/Conductor"
