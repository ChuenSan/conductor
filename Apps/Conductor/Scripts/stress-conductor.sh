#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

if [[ -x /usr/local/opt/swift/bin/swift ]]; then
  export PATH="/usr/local/opt/swift/bin:$PATH"
fi

STRESS_TMP="${CONDUCTOR_STRESS_TMPDIR:-$(mktemp -d /tmp/conductor-stress.XXXXXX)}"
KEEP_TMP="${CONDUCTOR_STRESS_KEEP_TMP:-0}"
APP_PID=""

cleanup() {
  if [[ -n "$APP_PID" ]] && kill -0 "$APP_PID" 2>/dev/null; then
    kill "$APP_PID" 2>/dev/null || true
    wait "$APP_PID" 2>/dev/null || true
  fi
  if [[ "$KEEP_TMP" != "1" && -n "${STRESS_TMP:-}" && -d "$STRESS_TMP" ]]; then
    rm -rf "$STRESS_TMP"
  fi
}
trap cleanup EXIT

section() {
  printf '\n== %s ==\n' "$*"
}

fail() {
  echo "stress-conductor.sh: $*" >&2
  if [[ -n "${APP_LOG:-}" && -f "$APP_LOG" ]]; then
    echo "---- app log ----" >&2
    tail -120 "$APP_LOG" >&2
  fi
  exit 1
}

require_line() {
  local file="$1"
  local expected="$2"
  if ! grep -qx "$expected" "$file"; then
    fail "expected '$expected' in $file"
  fi
}

extract_raw() {
  plutil -extract "$1" raw -o - -
}

capture() {
  echo "stress-conductor.sh: $*" >&2
  CONDUCTOR_CONTROL_SOCKET_PATH="$SOCKET_PATH" "$CLI_BIN" "$@"
}

run() {
  capture "$@" >/dev/null
}

wait_for_socket() {
  for _ in {1..90}; do
    if [[ -S "$SOCKET_PATH" ]]; then
      return 0
    fi
    if [[ -n "$APP_PID" ]] && ! kill -0 "$APP_PID" 2>/dev/null; then
      fail "Conductor exited before the control socket was ready."
    fi
    sleep 1
  done
  fail "control socket did not appear at $SOCKET_PATH"
}

require_int_at_least() {
  local value="$1"
  local minimum="$2"
  local label="$3"
  if [[ -z "$value" || "$value" -lt "$minimum" ]]; then
    fail "expected $label >= $minimum, got ${value:-<missing>}"
  fi
}

require_contains() {
  local value="$1"
  local expected="$2"
  local label="$3"
  if [[ "$value" != *"$expected"* ]]; then
    fail "expected $label to contain '$expected', got ${value:-<missing>}"
  fi
}

run_autorun() {
  local label="$1"
  local autorun_env="$2"
  local output_env="$3"
  shift 3

  local output="$STRESS_TMP/$label.txt"
  local log="$STRESS_TMP/$label.log"
  rm -f "$output" "$log"

  section "autorun: $label"
  env "$autorun_env=1" "$output_env=$output" "$APP_BIN" >"$log" 2>&1

  if [[ ! -s "$output" ]]; then
    echo "---- $log ----" >&2
    cat "$log" >&2
    fail "$label did not write $output"
  fi

  cat "$output"
  echo
  for expected in "$@"; do
    require_line "$output" "$expected"
  done
}

mkdir -p "$STRESS_TMP"
STATE_PATH="$STRESS_TMP/window-state.yaml"
SOCKET_PATH="$STRESS_TMP/control.sock"
APP_LOG="$STRESS_TMP/conductor.log"
FIXTURE_PATH="$ROOT/Scripts/fixtures/browser-automation.html"
FIXTURE_URL="file://${FIXTURE_PATH// /%20}"

if [[ "${CONDUCTOR_STRESS_SKIP_BUILD:-0}" != "1" ]]; then
  section "build"
  ./Scripts/prepare-ghosttykit.sh
  swift build --product Conductor
  swift build --product ConductorCLI
fi

BIN_PATH="$(swift build --show-bin-path)"
APP_BIN="${CONDUCTOR_BIN_PATH:-$BIN_PATH/Conductor}"
CLI_BIN="${CONDUCTOR_CLI_PATH:-$BIN_PATH/ConductorCLI}"

if [[ ! -x "$APP_BIN" || ! -x "$CLI_BIN" ]]; then
  fail "missing built Conductor or ConductorCLI binary"
fi

if [[ "${CONDUCTOR_STRESS_SKIP_AUTORUN:-0}" != "1" ]]; then
  run_autorun long-output CONDUCTOR_STRESS_AUTORUN CONDUCTOR_STRESS_OUTPUT \
    status=ok stress=long-output characters=65536 characters_per_terminal=65536 target_terminals=3 total_characters=196608 completed_terminals=3 panes=3 terminals=4 zoomed=false

  run_autorun resize-output CONDUCTOR_RESIZE_STRESS_AUTORUN CONDUCTOR_RESIZE_STRESS_OUTPUT \
    status=ok stress=resize-while-output resized=true panes=3 terminals=4 surfaces=4 zoomed=false
else
  section "autorun stress skipped"
fi

section "start isolated app"
CONDUCTOR_STATE_PATH="$STATE_PATH" \
CONDUCTOR_CONTROL_SOCKET_PATH="$SOCKET_PATH" \
"$APP_BIN" >"$APP_LOG" 2>&1 &
APP_PID="$!"
wait_for_socket
run ping

section "20 idle terminals"
TERMINAL_WORKSPACE_RESPONSE="$(capture workspace create --title "Stress Terminals")"
TERMINAL_WORKSPACE_ID="$(printf '%s' "$TERMINAL_WORKSPACE_RESPONSE" | extract_raw result.workspaceID)"
for index in $(seq 2 20); do
  run command run newTerminal
  if (( index % 5 == 0 )); then
    run terminal send --text "printf 'terminal stress $index ready\\n'\n"
  fi
done
WORKSPACE_LIST_RESPONSE="$(capture workspace list)"
SELECTED_WORKSPACE_ID="$(printf '%s' "$WORKSPACE_LIST_RESPONSE" | extract_raw result.selectedWorkspaceID)"
if [[ "$SELECTED_WORKSPACE_ID" != "$TERMINAL_WORKSPACE_ID" ]]; then
  fail "terminal stress workspace was not selected"
fi
WORKSPACE_LIST_JSON="$STRESS_TMP/workspace-list.json"
printf '%s' "$WORKSPACE_LIST_RESPONSE" >"$WORKSPACE_LIST_JSON"
TERMINAL_COUNT="$(python3 - "$TERMINAL_WORKSPACE_ID" "$WORKSPACE_LIST_JSON" <<'PY'
import json
import sys

target = sys.argv[1]
path = sys.argv[2]
with open(path, "r", encoding="utf-8") as handle:
    response = json.load(handle)
workspaces = response.get("result", {}).get("workspaces", [])
for workspace in workspaces:
    if workspace.get("id") == target:
        print(workspace.get("terminalCount", 0))
        break
else:
    print(0)
PY
)"
require_int_at_least "$TERMINAL_COUNT" 20 "terminalCount"

section "10 browser tabs"
BROWSER_WORKSPACE_RESPONSE="$(capture workspace create --title "Stress Browser")"
BROWSER_WORKSPACE_ID="$(printf '%s' "$BROWSER_WORKSPACE_RESPONSE" | extract_raw result.workspaceID)"
BROWSER_AUTOMATION_COUNT=0
for index in $(seq 1 10); do
  run browser open "$FIXTURE_URL?tab=$index"
  capture browser wait load --timeout 10 >/dev/null
  capture browser wait title "Conductor Browser Fixture" --timeout 5 >/dev/null
  capture browser fill "frame-0 >> #frame-query" "Stress frame $index" >/dev/null
  capture browser click "frame-0 >> #frame-run" >/dev/null
  capture browser wait text "frame-0 >> Frame completed: Stress frame $index" --timeout 5 >/dev/null
  FRAME_FIND_RESPONSE="$(capture browser find --frame frame-0 "Frame completed: Stress frame $index")"
  FRAME_FIND_MATCHES="$(printf '%s' "$FRAME_FIND_RESPONSE" | extract_raw result.matches)"
  require_int_at_least "$FRAME_FIND_MATCHES" 1 "frame find matches for browser tab $index"
  FRAME_EVALUATE_RESPONSE="$(capture browser evaluate --frame frame-0 "document.getElementById('frame-output').textContent")"
  FRAME_EVALUATE_RESULT="$(printf '%s' "$FRAME_EVALUATE_RESPONSE" | extract_raw result.result)"
  require_contains "$FRAME_EVALUATE_RESULT" "Frame completed: Stress frame $index" "frame evaluate result for browser tab $index"
  BROWSER_AUTOMATION_COUNT=$((BROWSER_AUTOMATION_COUNT + 1))
done
STATUS_AFTER_BROWSER="$(capture status)"
WEB_TAB_COUNT="$(printf '%s' "$STATUS_AFTER_BROWSER" | extract_raw result.webTabCount)"
require_int_at_least "$WEB_TAB_COUNT" 10 "webTabCount"
require_int_at_least "$BROWSER_AUTOMATION_COUNT" 10 "browser automation iterations"

section "rapid workspace switching"
for _ in $(seq 1 12); do
  run workspace select "$TERMINAL_WORKSPACE_ID"
  run workspace select "$BROWSER_WORKSPACE_ID"
done
DIAGNOSTICS_RESPONSE="$(capture diagnostics)"
SAMPLE_COUNT="$(printf '%s' "$DIAGNOSTICS_RESPONSE" | extract_raw result.performance.samples.recentCount)"
require_int_at_least "$SAMPLE_COUNT" 1 "performance sample count"

section "done"
echo "stress=ok"
echo "terminalCount=$TERMINAL_COUNT"
echo "webTabs=$WEB_TAB_COUNT"
echo "browserAutomationIterations=$BROWSER_AUTOMATION_COUNT"
echo "switches=24"
echo "artifacts=$STRESS_TMP"
