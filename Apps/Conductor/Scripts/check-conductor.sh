#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPO_ROOT="$(cd "$ROOT/../.." && pwd)"
cd "$ROOT"

if [[ -x /usr/local/opt/swift/bin/swift ]]; then
  export PATH="/usr/local/opt/swift/bin:$PATH"
fi

CHECK_TMP="${CONDUCTOR_CHECK_TMPDIR:-$(mktemp -d /tmp/conductor-check.XXXXXX)}"
KEEP_TMP="${CONDUCTOR_CHECK_KEEP_TMP:-0}"
mkdir -p "$CHECK_TMP"

cleanup() {
  if [[ "$KEEP_TMP" != "1" && -n "${CHECK_TMP:-}" && -d "$CHECK_TMP" ]]; then
    rm -rf "$CHECK_TMP"
  fi
}
trap cleanup EXIT

section() {
  printf '\n== %s ==\n' "$*"
}

require_line() {
  local file="$1"
  local expected="$2"
  if ! grep -qx "$expected" "$file"; then
    echo "check-conductor.sh: expected '$expected' in $file" >&2
    echo "---- $file ----" >&2
    cat "$file" >&2
    exit 1
  fi
}

run_autorun() {
  local label="$1"
  local autorun_env="$2"
  local output_env="$3"
  shift 3

  local output="$CHECK_TMP/$label.txt"
  local log="$CHECK_TMP/$label.log"
  local state_dir="$CHECK_TMP/$label-state"
  local state_path="$state_dir/window-state.yaml"
  mkdir -p "$state_dir"
  rm -f "$output" "$log"

  section "autorun: $label"
  env "$autorun_env=1" "$output_env=$output" "CONDUCTOR_STATE_PATH=$state_path" "$CONDUCTOR_BIN" >"$log" 2>&1

  if [[ ! -s "$output" ]]; then
    echo "check-conductor.sh: $label did not write $output" >&2
    echo "---- $log ----" >&2
    cat "$log" >&2
    exit 1
  fi

  cat "$output"
  echo
  for expected in "$@"; do
    require_line "$output" "$expected"
  done
}

section "prepare dependencies"
./Scripts/prepare-ghosttykit.sh

section "build"
if [[ "${CONDUCTOR_CHECK_SKIP_BUILD:-0}" != "1" ]]; then
  swift build --product Conductor
  swift build --product ConductorCLI
  swift build --product ConductorModelCheck
  BIN_PATH="$(swift build --show-bin-path)"
  CONDUCTOR_BIN="$BIN_PATH/Conductor"
  CONDUCTOR_CLI_BIN="$BIN_PATH/ConductorCLI"
  CONDUCTOR_MODEL_CHECK_BIN="$BIN_PATH/ConductorModelCheck"
else
  CONDUCTOR_BIN="${CONDUCTOR_BIN_PATH:-$ROOT/.build/debug/Conductor}"
  CONDUCTOR_CLI_BIN="${CONDUCTOR_CLI_PATH:-$ROOT/.build/debug/ConductorCLI}"
  CONDUCTOR_MODEL_CHECK_BIN="${CONDUCTOR_MODEL_CHECK_PATH:-$ROOT/.build/debug/ConductorModelCheck}"
  echo "reusing Conductor binary: $CONDUCTOR_BIN"
  echo "reusing ConductorCLI binary: $CONDUCTOR_CLI_BIN"
  echo "reusing ConductorModelCheck binary: $CONDUCTOR_MODEL_CHECK_BIN"
fi

if [[ ! -x "$CONDUCTOR_BIN" || ! -x "$CONDUCTOR_CLI_BIN" || ! -x "$CONDUCTOR_MODEL_CHECK_BIN" ]]; then
  echo "check-conductor.sh: missing built Conductor or ConductorCLI binary" >&2
  echo "Conductor: $CONDUCTOR_BIN" >&2
  echo "ConductorCLI: $CONDUCTOR_CLI_BIN" >&2
  echo "ConductorModelCheck: $CONDUCTOR_MODEL_CHECK_BIN" >&2
  exit 1
fi

section "model check"
"$CONDUCTOR_MODEL_CHECK_BIN"

if [[ "${CONDUCTOR_CHECK_SKIP_TESTS:-0}" != "1" ]]; then
  section "swift tests"
  ./Scripts/swift-test.sh
else
  section "swift tests skipped"
fi

section "control dogfood"
CONDUCTOR_DOGFOOD_SKIP_BUILD=1 \
CONDUCTOR_DOGFOOD_RUN_CONTROL_SMOKE=1 \
CONDUCTOR_DOGFOOD_TMPDIR="$CHECK_TMP/dogfood" \
CONDUCTOR_DOGFOOD_KEEP_TMP=1 \
CONDUCTOR_BIN_PATH="$CONDUCTOR_BIN" \
CONDUCTOR_CLI_PATH="$CONDUCTOR_CLI_BIN" \
./Scripts/dogfood-workbench.sh

if [[ "${CONDUCTOR_CHECK_SKIP_PERF_GATE:-0}" != "1" ]]; then
  section "performance gate"
  ./Scripts/performance-gate.sh "$CHECK_TMP/dogfood/diagnostics/summary.redacted.json"
else
  section "performance gate skipped"
fi

if [[ "${CONDUCTOR_CHECK_SKIP_STRESS:-0}" != "1" ]]; then
  section "protocol stress"
  CONDUCTOR_STRESS_SKIP_BUILD=1 \
  CONDUCTOR_STRESS_SKIP_AUTORUN=1 \
  CONDUCTOR_STRESS_TMPDIR="$CHECK_TMP/stress" \
  CONDUCTOR_STRESS_KEEP_TMP=1 \
  CONDUCTOR_BIN_PATH="$CONDUCTOR_BIN" \
  CONDUCTOR_CLI_PATH="$CONDUCTOR_CLI_BIN" \
  ./Scripts/stress-conductor.sh
else
  section "protocol stress skipped"
fi

if [[ "${CONDUCTOR_CHECK_SKIP_UPDATE_FIXTURE:-0}" != "1" ]]; then
  section "update fixture"
  CONDUCTOR_UPDATE_FIXTURE_SKIP_BUILD=1 \
  CONDUCTOR_UPDATE_FIXTURE_TMPDIR="$CHECK_TMP/update-fixture" \
  CONDUCTOR_UPDATE_FIXTURE_KEEP_TMP=1 \
  CONDUCTOR_BIN_PATH="$CONDUCTOR_BIN" \
  CONDUCTOR_CLI_PATH="$CONDUCTOR_CLI_BIN" \
  ./Scripts/update-fixture.sh
else
  section "update fixture skipped"
fi

if [[ "${CONDUCTOR_CHECK_SKIP_AUTORUN:-0}" != "1" ]]; then
  run_autorun smoke CONDUCTOR_SMOKE_AUTORUN CONDUCTOR_SMOKE_OUTPUT \
    status=ok panes=2 terminals=2 zoomed=false

  run_autorun shortcut CONDUCTOR_SHORTCUT_AUTORUN CONDUCTOR_SHORTCUT_OUTPUT \
    status=ok shortcut=perform-key-equivalent workspaceValid=true expectedShape=true panes=3 terminals=3 zoomed=true

  run_autorun shortcut-profile CONDUCTOR_SHORTCUT_PROFILE_AUTORUN CONDUCTOR_SHORTCUT_PROFILE_OUTPUT \
    status=ok shortcut-profile=import-export imported=3 unknown=1 rejected=1 conflicts=1 exported=2

  run_autorun menu CONDUCTOR_MENU_AUTORUN CONDUCTOR_MENU_OUTPUT \
    status=ok menu=canonical-actions checked=11

  run_autorun focus CONDUCTOR_FOCUS_AUTORUN CONDUCTOR_FOCUS_OUTPUT \
    status=ok focus=first-responder mouse-focus=workspace panes=2 terminals=3 zoomed=false

  run_autorun layout CONDUCTOR_LAYOUT_AUTORUN CONDUCTOR_LAYOUT_OUTPUT \
    status=ok layout=resize clamped=true equalized=true panes=3 terminals=3 zoomed=false

  run_autorun lifecycle CONDUCTOR_LIFECYCLE_AUTORUN CONDUCTOR_LIFECYCLE_OUTPUT \
    status=ok lifecycle=close surfaces=0 metadata=0 panes=1 terminals=1 zoomed=false

  run_autorun workspace CONDUCTOR_WORKSPACE_AUTORUN CONDUCTOR_WORKSPACE_OUTPUT \
    status=ok workspace=operations panes=2 terminals=2 zoomed=false

  run_autorun shell-panel CONDUCTOR_SHELL_PANEL_AUTORUN CONDUCTOR_SHELL_PANEL_OUTPUT \
    status=ok shell-panels=dismiss empty=true settings=true shortcut-blocked=true command=true overview=true terminal-search=true

  run_autorun notification CONDUCTOR_NOTIFICATION_AUTORUN CONDUCTOR_NOTIFICATION_OUTPUT \
    status=ok notification=native eventStored=true nativeDeliveryAttempted=true unreadCleared=true targetFocused=true

  run_autorun stress CONDUCTOR_STRESS_AUTORUN CONDUCTOR_STRESS_OUTPUT \
    status=ok stress=long-output characters=65536 characters_per_terminal=65536 target_terminals=3 total_characters=196608 completed_terminals=3 panes=3 terminals=4 zoomed=false

  run_autorun resize-stress CONDUCTOR_RESIZE_STRESS_AUTORUN CONDUCTOR_RESIZE_STRESS_OUTPUT \
    status=ok stress=resize-while-output resized=true panes=3 terminals=4 surfaces=4 zoomed=false
else
  section "autorun scenarios skipped"
fi

if [[ "${CONDUCTOR_CHECK_SKIP_BUNDLE:-0}" != "1" ]]; then
  section "app bundle"
  ./Scripts/build-app-bundle.sh >"$CHECK_TMP/app-bundle-path.txt"
  cat "$CHECK_TMP/app-bundle-path.txt"
else
  section "app bundle skipped"
fi

if [[ "${CONDUCTOR_CHECK_SKIP_SCREENSHOTS:-0}" != "1" ]]; then
  section "release screenshots"
  SCREENSHOT_OUTPUT_DIR="${CONDUCTOR_CHECK_SCREENSHOT_OUTPUT_DIR:-$CHECK_TMP/release-screenshots}"
  CONDUCTOR_SCREENSHOT_SKIP_BUILD=1 \
  CONDUCTOR_SCREENSHOT_TMPDIR="$CHECK_TMP/screenshot-runtime" \
  CONDUCTOR_SCREENSHOT_OUTPUT_DIR="$SCREENSHOT_OUTPUT_DIR" \
  CONDUCTOR_BIN_PATH="$CONDUCTOR_BIN" \
  CONDUCTOR_CLI_PATH="$CONDUCTOR_CLI_BIN" \
  ./Scripts/capture-release-screenshots.sh

  python3 - "$SCREENSHOT_OUTPUT_DIR/release-screenshots-manifest.json" "$REPO_ROOT" <<'PY'
import json
import os
import sys

manifest_path = sys.argv[1]
repo_root = sys.argv[2]
with open(manifest_path, "r", encoding="utf-8") as handle:
    manifest = json.load(handle)

screenshots = manifest.get("screenshots", [])
if len(screenshots) < 6:
    raise SystemExit(f"expected at least 6 release screenshots, got {len(screenshots)}")

missing = []
for item in screenshots:
    path = item.get("path")
    if not path:
        missing.append("<missing path>")
        continue
    if not os.path.isabs(path):
        path = os.path.join(repo_root, path)
    if not os.path.exists(path) or os.path.getsize(path) <= 0:
        missing.append(path)

if missing:
    raise SystemExit("missing or empty screenshots: " + ", ".join(missing))

print(f"screenshot_manifest=ok count={len(screenshots)}")
PY
else
  section "release screenshots skipped"
fi

section "trellis validation"
cd "$REPO_ROOT"
if [[ -f ".trellis/scripts/task.py" ]]; then
  python3 .trellis/scripts/task.py validate 05-15-conductor-macos-foundation
else
  echo "Skipping Trellis validation; .trellis is not present in this checkout."
fi

section "done"
echo "Conductor checks passed"
