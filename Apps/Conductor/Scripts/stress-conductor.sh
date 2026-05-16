#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

./Scripts/prepare-ghosttykit.sh
swift build

rm -f /tmp/conductor-stress-ok.txt
CONDUCTOR_STRESS_AUTORUN=1 \
CONDUCTOR_STRESS_OUTPUT=/tmp/conductor-stress-ok.txt \
swift run Conductor >/tmp/conductor-stress-run.log 2>&1

cat /tmp/conductor-stress-ok.txt
grep -qx 'status=ok' /tmp/conductor-stress-ok.txt
grep -qx 'stress=long-output' /tmp/conductor-stress-ok.txt
grep -qx 'panes=3' /tmp/conductor-stress-ok.txt
grep -qx 'terminals=4' /tmp/conductor-stress-ok.txt
grep -qx 'zoomed=false' /tmp/conductor-stress-ok.txt
