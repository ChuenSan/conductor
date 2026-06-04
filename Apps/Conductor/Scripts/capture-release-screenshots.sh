#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPO_ROOT="$(cd "$ROOT/../.." && pwd)"
cd "$ROOT"

if [[ -x /usr/local/opt/swift/bin/swift ]]; then
  export PATH="/usr/local/opt/swift/bin:$PATH"
fi

CAPTURE_TMP="${CONDUCTOR_SCREENSHOT_TMPDIR:-$(mktemp -d /tmp/conductor-screenshots.XXXXXX)}"
OUTPUT_DIR="${CONDUCTOR_SCREENSHOT_OUTPUT_DIR:-$REPO_ROOT/docs/media}"
KEEP_TMP="${CONDUCTOR_SCREENSHOT_KEEP_TMP:-0}"
APP_PID=""

cleanup() {
  if [[ -n "$APP_PID" ]] && kill -0 "$APP_PID" 2>/dev/null; then
    kill "$APP_PID" 2>/dev/null || true
    wait "$APP_PID" 2>/dev/null || true
  fi
  if [[ "$KEEP_TMP" != "1" && -n "${CAPTURE_TMP:-}" && -d "$CAPTURE_TMP" ]]; then
    rm -rf "$CAPTURE_TMP"
  fi
}
trap cleanup EXIT

section() {
  printf '\n== %s ==\n' "$*"
}

fail() {
  echo "capture-release-screenshots.sh: $*" >&2
  if [[ -n "${APP_LOG:-}" && -f "$APP_LOG" ]]; then
    echo "---- app log ----" >&2
    tail -120 "$APP_LOG" >&2
  fi
  exit 1
}

capture() {
  echo "capture-release-screenshots.sh: $*" >&2
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

window_id() {
  local title="${1:-}"
  if [[ -n "$title" ]]; then
    swift "$ROOT/Scripts/window-list.swift" Conductor --pid "$APP_PID" --title "$title" --first-id
  else
    swift "$ROOT/Scripts/window-list.swift" Conductor --pid "$APP_PID" --first-id
  fi
}

capture_window() {
  local name="$1"
  local mode="${2:-chrome}"
  local title="${3:-}"
  local path="$OUTPUT_DIR/$name"
  local id
  id="$(window_id "$title")"
  if [[ -z "$id" ]]; then
    fail "could not locate a visible Conductor window"
  fi

  mkdir -p "$OUTPUT_DIR"
  screencapture -x -o -l "$id" "$path"
  if [[ ! -s "$path" ]]; then
    fail "screencapture did not produce $path"
  fi
  swift "$ROOT/Scripts/redact-screenshot.swift" "$path" "$mode"
  sips -g pixelWidth -g pixelHeight "$path" >/dev/null
  echo "$path"
}

mkdir -p "$CAPTURE_TMP" "$OUTPUT_DIR"
STATE_PATH="$CAPTURE_TMP/window-state.yaml"
SOCKET_PATH="$CAPTURE_TMP/control.sock"
APP_LOG="$CAPTURE_TMP/conductor.log"
FIXTURE_PATH="$ROOT/Scripts/fixtures/browser-automation.html"
FIXTURE_URL="file://${FIXTURE_PATH// /%20}"
MANIFEST_PATH="$OUTPUT_DIR/release-screenshots-manifest.json"

if [[ "${CONDUCTOR_SCREENSHOT_SKIP_BUILD:-0}" != "1" ]]; then
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

section "start isolated app"
CONDUCTOR_STATE_PATH="$STATE_PATH" \
CONDUCTOR_CONTROL_SOCKET_PATH="$SOCKET_PATH" \
"$APP_BIN" >"$APP_LOG" 2>&1 &
APP_PID="$!"
wait_for_socket
run ping
sleep 2

section "prepare demo state"
run workspace create --title "Release Demo"
run surface split --direction right
run terminal send --text $'clear\nprintf "Conductor release capture\\nworkspace ready\\n"\n'
sleep 1

section "capture workbench"
WORKBENCH_PATH="$(capture_window conductor-screenshot-workbench.png workbench)"

section "capture token records"
run command run openTokenRecords
sleep 2
TOKEN_PATH="$(capture_window conductor-screenshot-token-records-panel.png token Token)"

run browser open "$FIXTURE_URL"
capture browser wait load --timeout 10 >/dev/null
sleep 1

section "capture browser"
BROWSER_PATH="$(capture_window conductor-screenshot-browser.png chrome)"

section "capture command palette"
run command run toggleCommandPalette
sleep 1
COMMAND_PATH="$(capture_window conductor-screenshot-command-palette.png chrome)"
run command run toggleCommandPalette

section "capture settings"
run command run toggleSettings
sleep 1
SETTINGS_PATH="$(capture_window conductor-screenshot-settings.png chrome)"

section "manifest"
python3 - "$MANIFEST_PATH" "$REPO_ROOT" "$WORKBENCH_PATH" "$TOKEN_PATH" "$NOTIFICATIONS_PATH" "$BROWSER_PATH" "$COMMAND_PATH" "$SETTINGS_PATH" <<'PY'
import json
import os
import sys
from datetime import datetime, timezone

manifest_path = sys.argv[1]
repo_root = sys.argv[2]
paths = sys.argv[3:]
payload = {
    "createdAt": datetime.now(timezone.utc).isoformat(),
    "source": "Apps/Conductor/Scripts/capture-release-screenshots.sh",
    "privacy": "Captured from an isolated Conductor state path and a Conductor window capture, not the full desktop.",
    "screenshots": [
        {
            "path": os.path.relpath(path, repo_root),
            "bytes": os.path.getsize(path),
        }
        for path in paths
    ],
}
with open(manifest_path, "w", encoding="utf-8") as handle:
    json.dump(payload, handle, indent=2, sort_keys=True)
    handle.write("\n")
PY

section "done"
echo "screenshots=ok"
echo "workbench=$WORKBENCH_PATH"
echo "tokenRecords=$TOKEN_PATH"
echo "notifications=$NOTIFICATIONS_PATH"
echo "browser=$BROWSER_PATH"
echo "commandPalette=$COMMAND_PATH"
echo "settings=$SETTINGS_PATH"
echo "manifest=$MANIFEST_PATH"
