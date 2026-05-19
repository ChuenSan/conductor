#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

if [[ -x /usr/local/opt/swift/bin/swift ]]; then
  export PATH="/usr/local/opt/swift/bin:$PATH"
fi

./Scripts/prepare-ghosttykit.sh
swift build
exec "$(swift build --show-bin-path)/Conductor"
