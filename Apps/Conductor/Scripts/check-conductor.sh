#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPO_ROOT="$(cd "$ROOT/../.." && pwd)"
cd "$ROOT"

if [[ -x /usr/local/opt/swift/bin/swift ]]; then
  export PATH="/usr/local/opt/swift/bin:$PATH"
fi

./Scripts/prepare-ghosttykit.sh
swift build
swift run ConductorModelCheck

STATE_FILE="$HOME/Library/Application Support/Conductor/window-state.json"
state_hash() {
  if [[ ! -f "$STATE_FILE" ]]; then
    echo "missing"
    return
  fi
  python3 - "$STATE_FILE" <<'PY' | shasum -a 256 | awk '{print $1}'
import json
import sys

with open(sys.argv[1], "r", encoding="utf-8") as handle:
    data = json.load(handle)
print(json.dumps(data, sort_keys=True, separators=(",", ":")))
PY
}

wait_for_conductor_exit() {
  local pattern="$ROOT/.build/x86_64-apple-macosx/debug/Conductor|$ROOT/.build/debug/Conductor|$ROOT/.build/Conductor.app/Contents/MacOS/Conductor"
  for _ in {1..40}; do
    if ! pgrep -fl "$pattern" >/tmp/conductor-wait-pids.txt; then
      return 0
    fi
    sleep 0.25
  done
  cat /tmp/conductor-wait-pids.txt >&2
  return 1
}

STATE_BEFORE="$(state_hash)"

rm -f /tmp/conductor-smoke-ok.txt
CONDUCTOR_SMOKE_AUTORUN=1 \
CONDUCTOR_SMOKE_OUTPUT=/tmp/conductor-smoke-ok.txt \
swift run Conductor >/tmp/conductor-smoke-run.log 2>&1
cat /tmp/conductor-smoke-ok.txt
echo
grep -qx 'status=ok' /tmp/conductor-smoke-ok.txt
grep -qx 'panes=2' /tmp/conductor-smoke-ok.txt
grep -qx 'terminals=2' /tmp/conductor-smoke-ok.txt
grep -qx 'zoomed=false' /tmp/conductor-smoke-ok.txt

rm -f /tmp/conductor-shortcut-ok.txt
CONDUCTOR_SHORTCUT_AUTORUN=1 \
CONDUCTOR_SHORTCUT_OUTPUT=/tmp/conductor-shortcut-ok.txt \
swift run Conductor >/tmp/conductor-shortcut-run.log 2>&1
cat /tmp/conductor-shortcut-ok.txt
echo
grep -qx 'status=ok' /tmp/conductor-shortcut-ok.txt
grep -qx 'shortcut=perform-key-equivalent' /tmp/conductor-shortcut-ok.txt

rm -f /tmp/conductor-focus-ok.txt
CONDUCTOR_FOCUS_AUTORUN=1 \
CONDUCTOR_FOCUS_OUTPUT=/tmp/conductor-focus-ok.txt \
swift run Conductor >/tmp/conductor-focus-run.log 2>&1
cat /tmp/conductor-focus-ok.txt
echo
grep -qx 'status=ok' /tmp/conductor-focus-ok.txt
grep -qx 'focus=first-responder' /tmp/conductor-focus-ok.txt
grep -qx 'mouse-focus=workspace' /tmp/conductor-focus-ok.txt
grep -qx 'panes=2' /tmp/conductor-focus-ok.txt
grep -qx 'terminals=3' /tmp/conductor-focus-ok.txt
grep -qx 'zoomed=false' /tmp/conductor-focus-ok.txt

rm -f /tmp/conductor-layout-ok.txt
CONDUCTOR_LAYOUT_AUTORUN=1 \
CONDUCTOR_LAYOUT_OUTPUT=/tmp/conductor-layout-ok.txt \
swift run Conductor >/tmp/conductor-layout-run.log 2>&1
cat /tmp/conductor-layout-ok.txt
echo
grep -qx 'status=ok' /tmp/conductor-layout-ok.txt
grep -qx 'layout=resize' /tmp/conductor-layout-ok.txt
grep -qx 'clamped=true' /tmp/conductor-layout-ok.txt
grep -qx 'equalized=true' /tmp/conductor-layout-ok.txt
grep -qx 'panes=3' /tmp/conductor-layout-ok.txt
grep -qx 'terminals=3' /tmp/conductor-layout-ok.txt
grep -qx 'zoomed=false' /tmp/conductor-layout-ok.txt

rm -f /tmp/conductor-lifecycle-ok.txt
CONDUCTOR_LIFECYCLE_AUTORUN=1 \
CONDUCTOR_LIFECYCLE_OUTPUT=/tmp/conductor-lifecycle-ok.txt \
swift run Conductor >/tmp/conductor-lifecycle-run.log 2>&1
cat /tmp/conductor-lifecycle-ok.txt
echo
grep -qx 'status=ok' /tmp/conductor-lifecycle-ok.txt
grep -qx 'lifecycle=close' /tmp/conductor-lifecycle-ok.txt
grep -qx 'surfaces=0' /tmp/conductor-lifecycle-ok.txt
grep -qx 'metadata=0' /tmp/conductor-lifecycle-ok.txt
grep -qx 'panes=1' /tmp/conductor-lifecycle-ok.txt
grep -qx 'terminals=1' /tmp/conductor-lifecycle-ok.txt
grep -qx 'zoomed=false' /tmp/conductor-lifecycle-ok.txt

rm -f /tmp/conductor-workspace-ok.txt
CONDUCTOR_WORKSPACE_AUTORUN=1 \
CONDUCTOR_WORKSPACE_OUTPUT=/tmp/conductor-workspace-ok.txt \
swift run Conductor >/tmp/conductor-workspace-run.log 2>&1
cat /tmp/conductor-workspace-ok.txt
echo
grep -qx 'status=ok' /tmp/conductor-workspace-ok.txt
grep -qx 'workspace=operations' /tmp/conductor-workspace-ok.txt
grep -qx 'panes=2' /tmp/conductor-workspace-ok.txt
grep -qx 'terminals=2' /tmp/conductor-workspace-ok.txt
grep -qx 'zoomed=false' /tmp/conductor-workspace-ok.txt

rm -f /tmp/conductor-shell-panel-ok.txt
CONDUCTOR_SHELL_PANEL_AUTORUN=1 \
CONDUCTOR_SHELL_PANEL_OUTPUT=/tmp/conductor-shell-panel-ok.txt \
swift run Conductor >/tmp/conductor-shell-panel-run.log 2>&1
cat /tmp/conductor-shell-panel-ok.txt
echo
grep -qx 'status=ok' /tmp/conductor-shell-panel-ok.txt
grep -qx 'shell-panels=dismiss' /tmp/conductor-shell-panel-ok.txt
grep -qx 'empty=true' /tmp/conductor-shell-panel-ok.txt
grep -qx 'settings=true' /tmp/conductor-shell-panel-ok.txt
grep -qx 'command=true' /tmp/conductor-shell-panel-ok.txt
grep -qx 'overview=true' /tmp/conductor-shell-panel-ok.txt

wait_for_conductor_exit

rm -f /tmp/conductor-notification-ok.txt
CONDUCTOR_NOTIFICATION_AUTORUN=1 \
CONDUCTOR_NOTIFICATION_OUTPUT=/tmp/conductor-notification-ok.txt \
swift run Conductor >/tmp/conductor-notification-run.log 2>&1
cat /tmp/conductor-notification-ok.txt
echo
grep -qx 'status=ok' /tmp/conductor-notification-ok.txt
grep -qx 'notification=open' /tmp/conductor-notification-ok.txt
grep -qx 'opened=true' /tmp/conductor-notification-ok.txt
grep -qx 'panelClosed=true' /tmp/conductor-notification-ok.txt
grep -qx 'unreadCleared=true' /tmp/conductor-notification-ok.txt
grep -qx 'targetFocused=true' /tmp/conductor-notification-ok.txt

wait_for_conductor_exit

rm -f /tmp/conductor-stress-ok.txt
CONDUCTOR_STRESS_AUTORUN=1 \
CONDUCTOR_STRESS_OUTPUT=/tmp/conductor-stress-ok.txt \
swift run Conductor >/tmp/conductor-stress-run.log 2>&1
cat /tmp/conductor-stress-ok.txt
echo
grep -qx 'status=ok' /tmp/conductor-stress-ok.txt
grep -qx 'stress=long-output' /tmp/conductor-stress-ok.txt
grep -qx 'panes=3' /tmp/conductor-stress-ok.txt
grep -qx 'terminals=4' /tmp/conductor-stress-ok.txt
grep -qx 'zoomed=false' /tmp/conductor-stress-ok.txt

wait_for_conductor_exit
sleep 1

rm -f /tmp/conductor-resize-stress-ok.txt
CONDUCTOR_RESIZE_STRESS_AUTORUN=1 \
CONDUCTOR_RESIZE_STRESS_OUTPUT=/tmp/conductor-resize-stress-ok.txt \
swift run Conductor >/tmp/conductor-resize-stress-run.log 2>&1
cat /tmp/conductor-resize-stress-ok.txt
echo
grep -qx 'status=ok' /tmp/conductor-resize-stress-ok.txt
grep -qx 'stress=resize-while-output' /tmp/conductor-resize-stress-ok.txt
grep -qx 'resized=true' /tmp/conductor-resize-stress-ok.txt
grep -qx 'panes=3' /tmp/conductor-resize-stress-ok.txt
grep -qx 'terminals=4' /tmp/conductor-resize-stress-ok.txt
grep -qx 'surfaces=4' /tmp/conductor-resize-stress-ok.txt
grep -qx 'zoomed=false' /tmp/conductor-resize-stress-ok.txt

STATE_AFTER="$(state_hash)"
if [[ "$STATE_BEFORE" != "$STATE_AFTER" ]]; then
  echo "Conductor smoke modified persisted user state" >&2
  echo "before=$STATE_BEFORE" >&2
  echo "after=$STATE_AFTER" >&2
  exit 1
fi

./Scripts/build-app-bundle.sh >/tmp/conductor-app-bundle-path.txt

cd "$REPO_ROOT"
python3 .trellis/scripts/task.py validate 05-15-conductor-macos-foundation

if pgrep -fl '/Users/uchihasasuke/Desktop/conductor/Apps/Conductor/.build/debug/Conductor|/Users/uchihasasuke/Desktop/conductor/Apps/Conductor/.build/Conductor.app/Contents/MacOS/Conductor|\.build/debug/Conductor|\.build/Conductor.app/Contents/MacOS/Conductor' >/tmp/conductor-leftover.txt; then
  cat /tmp/conductor-leftover.txt >&2
  exit 1
fi

echo "Conductor checks passed"
