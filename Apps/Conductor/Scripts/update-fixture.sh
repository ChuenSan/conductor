#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

if [[ -x /usr/local/opt/swift/bin/swift ]]; then
  export PATH="/usr/local/opt/swift/bin:$PATH"
fi

UPDATE_TMP="${CONDUCTOR_UPDATE_FIXTURE_TMPDIR:-$(mktemp -d /tmp/conductor-update-fixture.XXXXXX)}"
KEEP_TMP="${CONDUCTOR_UPDATE_FIXTURE_KEEP_TMP:-0}"
APP_PID=""

cleanup() {
  if [[ -n "$APP_PID" ]] && kill -0 "$APP_PID" 2>/dev/null; then
    kill "$APP_PID" 2>/dev/null || true
    wait "$APP_PID" 2>/dev/null || true
  fi
  if [[ "$KEEP_TMP" != "1" && -n "${UPDATE_TMP:-}" && -d "$UPDATE_TMP" ]]; then
    rm -rf "$UPDATE_TMP"
  fi
}
trap cleanup EXIT

section() {
  printf '\n== %s ==\n' "$*"
}

fail() {
  echo "update-fixture.sh: $*" >&2
  if [[ -n "${APP_LOG:-}" && -f "$APP_LOG" ]]; then
    echo "---- app log ----" >&2
    tail -120 "$APP_LOG" >&2
  fi
  exit 1
}

extract_raw() {
  plutil -extract "$1" raw -o - -
}

capture() {
  echo "update-fixture.sh: $*" >&2
  HOME="$HOME_DIR" CONDUCTOR_CONTROL_SOCKET_PATH="$SOCKET_PATH" "$CLI_BIN" "$@"
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

require_phase() {
  local response="$1"
  local expected="$2"
  local label="$3"
  local phase
  phase="$(printf '%s' "$response" | extract_raw result.phase 2>/dev/null || true)"
  if [[ "$phase" != "$expected" ]]; then
    echo "$response" >&2
    fail "expected $label phase '$expected', got '${phase:-<missing>}'"
  fi
}

require_can_download() {
  local response="$1"
  local label="$2"
  local can_download
  can_download="$(printf '%s' "$response" | extract_raw result.canDownload 2>/dev/null || true)"
  if [[ "$can_download" != "1" && "$can_download" != "true" ]]; then
    echo "$response" >&2
    fail "expected $label canDownload to be true, got '${can_download:-<missing>}'"
  fi
}

require_automatic_checks() {
  local response="$1"
  local label="$2"
  local enabled
  local failures
  enabled="$(printf '%s' "$response" | extract_raw result.automaticChecks.enabled 2>/dev/null || true)"
  failures="$(printf '%s' "$response" | extract_raw result.automaticChecks.consecutiveFailures 2>/dev/null || true)"
  if [[ "$enabled" != "1" && "$enabled" != "true" ]]; then
    echo "$response" >&2
    fail "expected $label automaticChecks.enabled to be true, got '${enabled:-<missing>}'"
  fi
  if [[ -z "$failures" ]]; then
    echo "$response" >&2
    fail "expected $label automaticChecks.consecutiveFailures to be present"
  fi
}

progress_increased() {
  python3 - "$@" <<'PY'
import sys

values = [float(value) for value in sys.argv[1:] if value]
if len(values) < 2:
    raise SystemExit(1)
if not any(value < 1.0 for value in values):
    raise SystemExit(1)
for previous, current in zip(values, values[1:]):
    if current > previous:
        raise SystemExit(0)
raise SystemExit(1)
PY
}

create_fixture_app() {
  local app_dir="$1"
  local version="$2"
  local build="$3"
  local label="$4"
  local size_mib="$5"
  rm -rf "$app_dir"
  mkdir -p "$app_dir/Contents/MacOS" "$app_dir/Contents/Resources"
  cat >"$app_dir/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key>
  <string>Conductor</string>
  <key>CFBundleIdentifier</key>
  <string>com.conductor.app</string>
  <key>CFBundleName</key>
  <string>Conductor</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>$version</string>
  <key>CFBundleVersion</key>
  <string>$build</string>
</dict>
</plist>
EOF
  cat >"$app_dir/Contents/MacOS/Conductor" <<'EOF'
#!/bin/sh
exit 0
EOF
  chmod +x "$app_dir/Contents/MacOS/Conductor"
  python3 - "$app_dir/Contents/Resources/$label-resource.bin" "$label" "$size_mib" <<'PY'
import os
import pathlib
import sys

path = pathlib.Path(sys.argv[1])
label = sys.argv[2].encode("utf-8")
size_mib = int(sys.argv[3])
with path.open("wb") as handle:
    handle.write(b"Conductor signed fixture app " + label + b"\n")
    for _ in range(size_mib):
        handle.write(os.urandom(1024 * 1024))
PY
  /usr/bin/codesign --force --sign - "$app_dir" >/dev/null
}

create_fixture_package() {
  local version="$1"
  local build="$2"
  local label="$3"
  local size_mib="${4:-4}"
  local payload="$FIXTURE_DIR/$label-payload.bin"
  local filename="Conductor-$version-$build-macos-$ARCH.zip"
  local artifact="$FIXTURE_DIR/$filename"
  python3 - "$payload" "$label" "$size_mib" <<'PY'
import os
import pathlib
import sys

path = pathlib.Path(sys.argv[1])
label = sys.argv[2].encode("utf-8")
size_mib = int(sys.argv[3])
with path.open("wb") as handle:
    handle.write(b"Conductor update fixture " + label + b"\n")
    for _ in range(size_mib):
        handle.write(os.urandom(1024 * 1024))
PY
  /usr/bin/zip -0 -q -j "$artifact" "$payload"
  rm -f "$payload"
  create_fixture_manifest "$version" "$build" "$label" "$filename" "$artifact"
}

create_fixture_app_package() {
  local version="$1"
  local build="$2"
  local label="$3"
  local size_mib="${4:-4}"
  local app_dir="$FIXTURE_DIR/$label/Conductor.app"
  local filename="Conductor-$version-$build-macos-$ARCH.zip"
  local artifact="$FIXTURE_DIR/$filename"
  mkdir -p "$FIXTURE_DIR/$label"
  create_fixture_app "$app_dir" "$version" "$build" "$label" "$size_mib"
  rm -f "$artifact"
  (cd "$FIXTURE_DIR/$label" && /usr/bin/zip -0 -q -r "$artifact" "Conductor.app")
  create_fixture_manifest "$version" "$build" "$label" "$filename" "$artifact"
}

create_fixture_manifest() {
  local version="$1"
  local build="$2"
  local label="$3"
  local filename="$4"
  local artifact="$5"
  local sha
  sha="$(shasum -a 256 "$artifact" | awk '{print $1}')"
  local size
  size="$(stat -f%z "$artifact")"
  local manifest="$FIXTURE_DIR/latest-$label.json"
  cat >"$manifest" <<EOF
{
  "schemaVersion": 1,
  "app": "Conductor",
  "bundleIdentifier": "com.conductor.app",
  "platform": "macos",
  "arch": "$ARCH",
  "channel": "fixture",
  "version": "$version",
  "build": "$build",
  "createdAt": "2026-06-03T00:00:00Z",
  "minimumSystemVersion": "14.0",
  "full": {
    "filename": "$filename",
    "sha256": "$sha",
    "size": $size
  }
}
EOF
  printf '%s\n' "$manifest"
}

mkdir -p "$UPDATE_TMP"
HOME_DIR="$UPDATE_TMP/home"
STATE_PATH="$UPDATE_TMP/window-state.yaml"
SOCKET_PATH="$UPDATE_TMP/control.sock"
APP_LOG="$UPDATE_TMP/conductor.log"
FIXTURE_DIR="$UPDATE_TMP/fixture"
DOWNLOAD_DIR="$UPDATE_TMP/downloads"
DIAGNOSTICS_DIR="$UPDATE_TMP/diagnostics"
ARCH="$(uname -m)"
mkdir -p "$HOME_DIR" "$FIXTURE_DIR" "$DOWNLOAD_DIR"

section "fixture packages"
CANCEL_MANIFEST="$(create_fixture_package "9.9.8" "998" "cancel" 12)"
CURRENT_APP_FIXTURE="$FIXTURE_DIR/current/Conductor.app"
create_fixture_app "$CURRENT_APP_FIXTURE" "0.0.1" "1" "current" 1
AVAILABLE_MANIFEST="$(create_fixture_app_package "9.9.9" "999" "available" 12)"
TAMPERED_MANIFEST="$(create_fixture_package "9.9.10" "1000" "tampered" 1)"
TAMPERED_ARTIFACT="$(python3 - "$TAMPERED_MANIFEST" <<'PY'
import json
import pathlib
import sys

manifest = pathlib.Path(sys.argv[1])
data = json.loads(manifest.read_text(encoding="utf-8"))
print(manifest.parent / data["full"]["filename"])
PY
)"
printf 'tampered bytes\n' >>"$TAMPERED_ARTIFACT"

if [[ "${CONDUCTOR_UPDATE_FIXTURE_SKIP_BUILD:-0}" != "1" ]]; then
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
HOME="$HOME_DIR" \
CONDUCTOR_STATE_PATH="$STATE_PATH" \
CONDUCTOR_CONTROL_SOCKET_PATH="$SOCKET_PATH" \
CONDUCTOR_UPDATE_DIRECTORY="$DOWNLOAD_DIR" \
CONDUCTOR_UPDATE_CURRENT_APP="$CURRENT_APP_FIXTURE" \
CONDUCTOR_UPDATE_LOCAL_COPY_DELAY_MS="${CONDUCTOR_UPDATE_FIXTURE_LOCAL_COPY_DELAY_MS:-120}" \
CONDUCTOR_UPDATE_MANIFEST_URL="$AVAILABLE_MANIFEST" \
"$APP_BIN" >"$APP_LOG" 2>&1 &
APP_PID="$!"
wait_for_socket
capture ping >/dev/null

section "initial status"
STATUS_RESPONSE="$(capture update status)"
INITIAL_PHASE="$(printf '%s' "$STATUS_RESPONSE" | extract_raw result.phase 2>/dev/null || true)"
if [[ -z "$INITIAL_PHASE" ]]; then
  echo "$STATUS_RESPONSE" >&2
  fail "initial update status did not include a phase"
fi
require_automatic_checks "$STATUS_RESPONSE" "initial status"

section "cancel in-flight download"
CANCEL_CHECK_RESPONSE="$(capture update check --manifest "$CANCEL_MANIFEST" --timeout 20)"
require_phase "$CANCEL_CHECK_RESPONSE" "available" "cancel check"
require_can_download "$CANCEL_CHECK_RESPONSE" "cancel check"
CANCEL_RESPONSE_FILE="$UPDATE_TMP/cancel-download-response.json"
CANCEL_LOG="$UPDATE_TMP/cancel-download.log"
echo "update-fixture.sh: update download --timeout 60" >&2
HOME="$HOME_DIR" CONDUCTOR_CONTROL_SOCKET_PATH="$SOCKET_PATH" "$CLI_BIN" update download --timeout 60 >"$CANCEL_RESPONSE_FILE" 2>"$CANCEL_LOG" &
CANCEL_PID="$!"
CANCEL_PROGRESS_SAMPLES=()
for _ in {1..100}; do
  if ! kill -0 "$CANCEL_PID" 2>/dev/null; then
    break
  fi
  STATUS_RESPONSE="$(capture update status)"
  PHASE="$(printf '%s' "$STATUS_RESPONSE" | extract_raw result.phase 2>/dev/null || true)"
  FRACTION="$(printf '%s' "$STATUS_RESPONSE" | extract_raw result.downloadProgress.fraction 2>/dev/null || true)"
  if [[ "$PHASE" == "downloading" && -n "$FRACTION" ]]; then
    CANCEL_PROGRESS_SAMPLES+=("$FRACTION")
    break
  fi
  sleep 0.08
done
if [[ "${#CANCEL_PROGRESS_SAMPLES[@]}" -lt 1 ]]; then
  cat "$CANCEL_LOG" >&2 || true
  fail "cancel download did not enter a visible downloading state before completion"
fi
CANCEL_RESPONSE="$(capture update cancel)"
require_phase "$CANCEL_RESPONSE" "available" "cancel response"
require_can_download "$CANCEL_RESPONSE" "cancel response"
if ! wait "$CANCEL_PID"; then
  cat "$CANCEL_LOG" >&2 || true
  fail "cancelled download command failed"
fi
CANCEL_DOWNLOAD_RESPONSE="$(cat "$CANCEL_RESPONSE_FILE")"
require_phase "$CANCEL_DOWNLOAD_RESPONSE" "available" "cancelled download"
require_can_download "$CANCEL_DOWNLOAD_RESPONSE" "cancelled download"
STATUS_AFTER_CANCEL="$(capture update status)"
require_phase "$STATUS_AFTER_CANCEL" "available" "status after cancel"
require_can_download "$STATUS_AFTER_CANCEL" "status after cancel"

section "available update"
CHECK_RESPONSE="$(capture update check --manifest "$AVAILABLE_MANIFEST" --timeout 20)"
require_phase "$CHECK_RESPONSE" "available" "available check"
AVAILABLE_VERSION="$(printf '%s' "$CHECK_RESPONSE" | extract_raw result.availableVersion)"

section "download update"
DOWNLOAD_RESPONSE_FILE="$UPDATE_TMP/download-response.json"
DOWNLOAD_LOG="$UPDATE_TMP/download.log"
echo "update-fixture.sh: update download --timeout 60" >&2
HOME="$HOME_DIR" CONDUCTOR_CONTROL_SOCKET_PATH="$SOCKET_PATH" "$CLI_BIN" update download --timeout 60 >"$DOWNLOAD_RESPONSE_FILE" 2>"$DOWNLOAD_LOG" &
DOWNLOAD_PID="$!"
PROGRESS_SAMPLES=()
for _ in {1..100}; do
  if ! kill -0 "$DOWNLOAD_PID" 2>/dev/null; then
    break
  fi
  STATUS_RESPONSE="$(capture update status)"
  PHASE="$(printf '%s' "$STATUS_RESPONSE" | extract_raw result.phase 2>/dev/null || true)"
  FRACTION="$(printf '%s' "$STATUS_RESPONSE" | extract_raw result.downloadProgress.fraction 2>/dev/null || true)"
  if [[ "$PHASE" == "downloading" && -n "$FRACTION" ]]; then
    PROGRESS_SAMPLES+=("$FRACTION")
    if progress_increased "${PROGRESS_SAMPLES[@]}"; then
      break
    fi
  fi
  sleep 0.08
done
if ! wait "$DOWNLOAD_PID"; then
  cat "$DOWNLOAD_LOG" >&2 || true
  fail "download command failed"
fi
DOWNLOAD_RESPONSE="$(cat "$DOWNLOAD_RESPONSE_FILE")"
require_phase "$DOWNLOAD_RESPONSE" "downloaded" "download"
if ! progress_increased "${PROGRESS_SAMPLES[@]}"; then
  printf 'progress samples: %s\n' "${PROGRESS_SAMPLES[*]:-<none>}" >&2
  fail "download progress did not produce at least two increasing samples before completion"
fi
DOWNLOADED_PATH="$(printf '%s' "$DOWNLOAD_RESPONSE" | extract_raw result.downloadedPackagePath)"
if [[ ! -s "$DOWNLOADED_PATH" ]]; then
  fail "downloaded package is missing or empty at $DOWNLOADED_PATH"
fi

section "install rehearsal"
REHEARSAL_RESPONSE="$(capture update rehearse-install)"
REHEARSAL_STATUS="$(printf '%s' "$REHEARSAL_RESPONSE" | extract_raw result.installRehearsal.exitStatus 2>/dev/null || true)"
REHEARSAL_LOG="$(printf '%s' "$REHEARSAL_RESPONSE" | extract_raw result.installRehearsal.logPath 2>/dev/null || true)"
if [[ "$REHEARSAL_STATUS" != "0" ]]; then
  echo "$REHEARSAL_RESPONSE" >&2
  fail "install rehearsal did not report exit status 0"
fi
if [[ -z "$REHEARSAL_LOG" || ! -s "$REHEARSAL_LOG" ]]; then
  echo "$REHEARSAL_RESPONSE" >&2
  fail "install rehearsal log is missing"
fi
if ! /usr/bin/grep -q "dry run verified staged app" "$REHEARSAL_LOG"; then
  cat "$REHEARSAL_LOG" >&2 || true
  fail "install rehearsal log did not include staged app verification"
fi

section "checksum failure"
BAD_CHECK_RESPONSE="$(capture update check --manifest "$TAMPERED_MANIFEST" --timeout 20)"
require_phase "$BAD_CHECK_RESPONSE" "available" "tampered check"
BAD_DOWNLOAD_RESPONSE="$(capture update download --timeout 45)"
require_phase "$BAD_DOWNLOAD_RESPONSE" "failed" "tampered download"

section "performance gate"
DIAGNOSTICS_RESPONSE="$(capture diagnostics export --output "$DIAGNOSTICS_DIR")"
DIAGNOSTICS_PATH="$(printf '%s' "$DIAGNOSTICS_RESPONSE" | extract_raw result.path)"
if [[ ! -s "$DIAGNOSTICS_PATH/summary.redacted.json" ]]; then
  echo "$DIAGNOSTICS_RESPONSE" >&2
  fail "diagnostics export did not produce a summary for performance gate"
fi
CONDUCTOR_PERF_GATE_REQUIRED_BUDGETS=update.check \
CONDUCTOR_PERF_GATE_ENFORCED_BUDGETS=update.check \
CONDUCTOR_PERF_GATE_MIN_SAMPLED_BUDGETS=1 \
CONDUCTOR_PERF_GATE_MIN_RECENT_SAMPLES=2 \
./Scripts/performance-gate.sh "$DIAGNOSTICS_PATH/summary.redacted.json"

section "done"
echo "update_fixture=ok"
echo "available=$AVAILABLE_VERSION"
echo "downloaded=$DOWNLOADED_PATH"
echo "cancelled=ok"
echo "cancel_progress_samples=${#CANCEL_PROGRESS_SAMPLES[@]}"
echo "progress_samples=${#PROGRESS_SAMPLES[@]}"
echo "install_rehearsal=ok"
echo "tampered=failed"
echo "performance_gate=ok"
echo "artifacts=$UPDATE_TMP"
