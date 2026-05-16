#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

./Scripts/prepare-ghosttykit.sh
swift build
exec ./.build/debug/Conductor
