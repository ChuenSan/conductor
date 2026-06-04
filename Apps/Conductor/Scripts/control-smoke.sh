#!/bin/bash
# Smoke-test the local control socket against a running Conductor app.
#
# Usage:
#   ./Scripts/control-smoke.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
SOCKET_PATH="${CONDUCTOR_CONTROL_SOCKET_PATH:-$HOME/Library/Application Support/Conductor/control.sock}"
FILE_FIXTURE_DIR=""
DEV_SERVER_PID=""
DEV_SERVER_PORT=""

cleanup() {
  if [[ -n "$DEV_SERVER_PID" ]]; then
    kill "$DEV_SERVER_PID" >/dev/null 2>&1 || true
    wait "$DEV_SERVER_PID" >/dev/null 2>&1 || true
  fi
  if [[ -n "$FILE_FIXTURE_DIR" && -d "$FILE_FIXTURE_DIR" ]]; then
    rm -rf "$FILE_FIXTURE_DIR"
  fi
}
trap cleanup EXIT

if [ ! -S "$SOCKET_PATH" ]; then
  echo "control-smoke.sh: control socket is not available at:" >&2
  echo "  $SOCKET_PATH" >&2
  echo "Start the app first, then run this script again." >&2
  exit 1
fi

cd "$PROJECT_DIR"
CLI="${CONDUCTOR_CLI_PATH:-$PROJECT_DIR/.build/debug/ConductorCLI}"

if [ "${CONDUCTOR_SMOKE_SKIP_CLI_BUILD:-0}" = "1" ] && [ -x "$CLI" ]; then
  echo "control-smoke.sh: reuse existing ConductorCLI"
else
  echo "control-smoke.sh: build ConductorCLI"
  swift build --product ConductorCLI >/dev/null
  CLI="${CONDUCTOR_CLI_PATH:-$PROJECT_DIR/.build/debug/ConductorCLI}"
fi

if [ ! -x "$CLI" ]; then
  echo "control-smoke.sh: missing CLI binary at $CLI" >&2
  exit 1
fi

echo "control-smoke.sh: ping"
if ! "$CLI" ping >/dev/null; then
  echo "control-smoke.sh: Conductor did not answer the control ping." >&2
  echo "The socket file may be stale; start the app and run this script again." >&2
  exit 1
fi

run() {
  echo "control-smoke.sh: $*"
  "$CLI" "$@" >/dev/null
}

capture() {
  echo "control-smoke.sh: $*" >&2
  "$CLI" "$@"
}

extract_raw() {
  plutil -extract "$1" raw -o - -
}

browser_tab_id_for_url() {
  local expected_url="$1"
  local response
  response="$(capture surface list)"
  local index
  for index in $(seq 0 40); do
    local type
    local url
    local web_tab_id
    type="$(printf '%s' "$response" | extract_raw "result.surfaces.$index.type" 2>/dev/null || true)"
    url="$(printf '%s' "$response" | extract_raw "result.surfaces.$index.url" 2>/dev/null || true)"
    web_tab_id="$(printf '%s' "$response" | extract_raw "result.surfaces.$index.webTabID" 2>/dev/null || true)"
    if [[ "$type" == "browser" && "$url" == "$expected_url" && -n "$web_tab_id" ]]; then
      printf '%s\n' "$web_tab_id"
      return 0
    fi
  done
  return 1
}

browser_download_field_for_tab() {
  local web_tab_id="$1"
  local field="$2"
  local response
  response="$(capture surface list)"
  local index
  for index in $(seq 0 80); do
    local type
    local candidate_web_tab_id
    type="$(printf '%s' "$response" | extract_raw "result.surfaces.$index.type" 2>/dev/null || true)"
    candidate_web_tab_id="$(printf '%s' "$response" | extract_raw "result.surfaces.$index.webTabID" 2>/dev/null || true)"
    if [[ "$type" == "browser" && "$candidate_web_tab_id" == "$web_tab_id" ]]; then
      printf '%s' "$response" | extract_raw "result.surfaces.$index.download.$field" 2>/dev/null || true
      return 0
    fi
  done
  return 1
}

browser_runtime_event_count_for_tab() {
  local web_tab_id="$1"
  local response
  response="$(capture surface list)"
  local index
  for index in $(seq 0 80); do
    local type
    local candidate_web_tab_id
    type="$(printf '%s' "$response" | extract_raw "result.surfaces.$index.type" 2>/dev/null || true)"
    candidate_web_tab_id="$(printf '%s' "$response" | extract_raw "result.surfaces.$index.webTabID" 2>/dev/null || true)"
    if [[ "$type" == "browser" && "$candidate_web_tab_id" == "$web_tab_id" ]]; then
      printf '%s' "$response" | extract_raw "result.surfaces.$index.runtimeEventCount" 2>/dev/null || true
      return 0
    fi
  done
  return 1
}

wait_for_file_buffer_available() {
  local target="$1"
  local attempt
  for attempt in $(seq 1 20); do
    local response
    local available
    response="$(capture file snapshot --target "$target")"
    available="$(printf '%s' "$response" | extract_raw result.file.buffer.available 2>/dev/null || true)"
    if [[ "$available" == "true" ]]; then
      printf '%s' "$response"
      return 0
    fi
    sleep 0.25
  done
  echo "control-smoke.sh: file buffer did not become available for $target" >&2
  return 1
}

session_surface_issue_field() {
  local kind="$1"
  local field="$2"
  local response="$3"
  local index
  for index in $(seq 0 80); do
    local candidate_kind
    candidate_kind="$(printf '%s' "$response" | extract_raw "result.surfaceIssues.$index.kind" 2>/dev/null || true)"
    if [[ "$candidate_kind" == "$kind" ]]; then
      printf '%s' "$response" | extract_raw "result.surfaceIssues.$index.$field" 2>/dev/null || true
      return 0
    fi
  done
  return 1
}

notification_field_by_id() {
  local notification_id="$1"
  local field="$2"
  local response
  response="$(capture notify list)"
  local index
  for index in $(seq 0 120); do
    local candidate_notification_id
    candidate_notification_id="$(printf '%s' "$response" | extract_raw "result.notifications.$index.id" 2>/dev/null || true)"
    if [[ "$candidate_notification_id" == "$notification_id" ]]; then
      printf '%s' "$response" | extract_raw "result.notifications.$index.$field" 2>/dev/null || true
      return 0
    fi
  done
  return 1
}

command_field_by_id() {
  local response="$1"
  local command_id="$2"
  local field="$3"
  local index
  for index in $(seq 0 120); do
    local candidate_command_id
    candidate_command_id="$(printf '%s' "$response" | extract_raw "result.commands.$index.id" 2>/dev/null || true)"
    if [[ "$candidate_command_id" == "$command_id" ]]; then
      printf '%s' "$response" | extract_raw "result.commands.$index.$field" 2>/dev/null || true
      return 0
    fi
  done
  return 1
}

recent_performance_budget_seen() {
  local response="$1"
  local budget_id="$2"
  local index
  for index in $(seq 0 80); do
    local candidate_budget_id
    candidate_budget_id="$(printf '%s' "$response" | extract_raw "result.performance.samples.recent.$index.budgetID" 2>/dev/null || true)"
    if [[ "$candidate_budget_id" == "$budget_id" ]]; then
      return 0
    fi
  done
  return 1
}

wait_for_browser_download_finished() {
  local web_tab_id="$1"
  local phase=""
  for _ in {1..80}; do
    phase="$(browser_download_field_for_tab "$web_tab_id" phase || true)"
    if [[ "$phase" == "finished" ]]; then
      return 0
    fi
    sleep 0.25
  done
  echo "control-smoke.sh: browser download did not finish for tab $web_tab_id, latest phase '${phase:-<missing>}'" >&2
  return 1
}

focused_terminal_id() {
  local response
  response="$(capture surface list)"
  printf '%s' "$response" | extract_raw "result.focusedTerminalID" 2>/dev/null || true
}

terminal_workspace_id() {
  local terminal_id="$1"
  local response
  response="$(capture surface list)"
  local index
  for index in $(seq 0 80); do
    local candidate_terminal_id
    local workspace_id
    candidate_terminal_id="$(printf '%s' "$response" | extract_raw "result.surfaces.$index.terminalID" 2>/dev/null || true)"
    workspace_id="$(printf '%s' "$response" | extract_raw "result.surfaces.$index.workspaceID" 2>/dev/null || true)"
    if [[ "$candidate_terminal_id" == "$terminal_id" && -n "$workspace_id" ]]; then
      printf '%s\n' "$workspace_id"
      return 0
    fi
  done
  return 1
}

first_unfocused_terminal_id() {
  local focused_id="$1"
  local workspace_id="$2"
  local response
  response="$(capture surface list)"
  local index
  for index in $(seq 0 80); do
    local type
    local terminal_id
    local candidate_workspace_id
    type="$(printf '%s' "$response" | extract_raw "result.surfaces.$index.type" 2>/dev/null || true)"
    terminal_id="$(printf '%s' "$response" | extract_raw "result.surfaces.$index.terminalID" 2>/dev/null || true)"
    candidate_workspace_id="$(printf '%s' "$response" | extract_raw "result.surfaces.$index.workspaceID" 2>/dev/null || true)"
    if [[ "$type" == "terminal" &&
          "$candidate_workspace_id" == "$workspace_id" &&
          -n "$terminal_id" &&
          "$terminal_id" != "$focused_id" ]]; then
      printf '%s\n' "$terminal_id"
      return 0
    fi
  done
  return 1
}

wait_for_command_finished_notification() {
  local terminal_id="$1"
  local response
  local index
  for _ in $(seq 1 40); do
    response="$(capture notify list)"
    for index in $(seq 0 80); do
      local id
      local kind
      local source
      local event_terminal_id
      local exit_code
      id="$(printf '%s' "$response" | extract_raw "result.notifications.$index.id" 2>/dev/null || true)"
      kind="$(printf '%s' "$response" | extract_raw "result.notifications.$index.kind" 2>/dev/null || true)"
      source="$(printf '%s' "$response" | extract_raw "result.notifications.$index.source" 2>/dev/null || true)"
      event_terminal_id="$(printf '%s' "$response" | extract_raw "result.notifications.$index.terminalID" 2>/dev/null || true)"
      exit_code="$(printf '%s' "$response" | extract_raw "result.notifications.$index.details.exitCode" 2>/dev/null || true)"
      if [[ "$kind" == "commandFinished" &&
            "$source" == "terminal-command" &&
            "$event_terminal_id" == "$terminal_id" &&
            "$exit_code" == "1" &&
            -n "$id" ]]; then
        printf '%s\n' "$id"
        return 0
      fi
    done
    sleep 0.25
  done
  if [[ -n "${response:-}" ]]; then
    echo "control-smoke.sh: latest notifications while waiting for commandFinished:" >&2
    echo "$response" >&2
  fi
  return 1
}

assert_contains() {
  local haystack="$1"
  local needle="$2"
  local label="$3"
  if [[ "$haystack" != *"$needle"* ]]; then
    echo "control-smoke.sh: expected $label to contain '$needle'" >&2
    exit 1
  fi
}

expect_error_code() {
  local expected="$1"
  shift
  local response
  echo "control-smoke.sh: expect $expected from $*" >&2
  if response="$("$CLI" "$@")"; then
    echo "control-smoke.sh: expected command to fail with $expected: $*" >&2
    exit 1
  fi
  local actual
  actual="$(printf '%s' "$response" | extract_raw error.details.automationError 2>/dev/null || true)"
  if [ "$actual" != "$expected" ]; then
    echo "control-smoke.sh: expected automationError '$expected' but got '${actual:-<missing>}'" >&2
    echo "$response" >&2
    exit 1
  fi
}

expect_control_error() {
  local expected="$1"
  shift
  local response
  echo "control-smoke.sh: expect control error $expected from $*" >&2
  if response="$("$CLI" "$@")"; then
    echo "control-smoke.sh: expected command to fail with $expected: $*" >&2
    exit 1
  fi
  local actual
  actual="$(printf '%s' "$response" | extract_raw error.code 2>/dev/null || true)"
  if [ "$actual" != "$expected" ]; then
    echo "control-smoke.sh: expected error '$expected' but got '${actual:-<missing>}'" >&2
    echo "$response" >&2
    exit 1
  fi
}

expect_control_error_detail() {
  local expected="$1"
  local detail_key="$2"
  local expected_detail="$3"
  shift 3
  local response
  echo "control-smoke.sh: expect control error $expected with $detail_key from $*" >&2
  if response="$("$CLI" "$@")"; then
    echo "control-smoke.sh: expected command to fail with $expected: $*" >&2
    exit 1
  fi
  local actual
  actual="$(printf '%s' "$response" | extract_raw error.code 2>/dev/null || true)"
  if [ "$actual" != "$expected" ]; then
    echo "control-smoke.sh: expected error '$expected' but got '${actual:-<missing>}'" >&2
    echo "$response" >&2
    exit 1
  fi
  local actual_detail
  actual_detail="$(printf '%s' "$response" | extract_raw "error.details.$detail_key" 2>/dev/null || true)"
  if [ "$actual_detail" != "$expected_detail" ]; then
    echo "control-smoke.sh: expected error.details.$detail_key '$expected_detail' but got '${actual_detail:-<missing>}'" >&2
    echo "$response" >&2
    exit 1
  fi
}

start_dev_server_fixture() {
  if ! command -v python3 >/dev/null 2>&1; then
    echo "control-smoke.sh: python3 is required for dev server metadata smoke" >&2
    exit 1
  fi

  local port
  for port in 18765 18766 18767 18768 18769; do
    if lsof -nP -iTCP:"$port" -sTCP:LISTEN >/dev/null 2>&1; then
      continue
    fi
    cat >"$FILE_FIXTURE_DIR/conductor-smoke-server.py" <<'PY'
import functools
import http.server
import os
import socketserver
import sys

port = int(sys.argv[1])
root = os.getcwd()
download_name = "conductor-browser-download-fixture.bin"

class Handler(http.server.SimpleHTTPRequestHandler):
    def do_GET(self):
        if self.path.split("?", 1)[0].lstrip("/") == download_name:
            path = os.path.join(root, download_name)
            self.send_response(200)
            self.send_header("Content-Type", "application/octet-stream")
            self.send_header("Content-Disposition", f"attachment; filename={download_name}")
            self.send_header("Content-Length", str(os.path.getsize(path)))
            self.end_headers()
            with open(path, "rb") as handle:
                self.copyfile(handle, self.wfile)
            return
        super().do_GET()

class ReusableTCPServer(socketserver.TCPServer):
    allow_reuse_address = True

handler = functools.partial(Handler, directory=root)
with ReusableTCPServer(("127.0.0.1", port), handler) as server:
    server.serve_forever()
PY
    (
      cd "$FILE_FIXTURE_DIR"
      python3 conductor-smoke-server.py "$port" >/dev/null 2>&1
    ) &
    DEV_SERVER_PID="$!"
    DEV_SERVER_PORT="$port"
    sleep 0.6
    if kill -0 "$DEV_SERVER_PID" >/dev/null 2>&1 &&
       lsof -nP -iTCP:"$port" -sTCP:LISTEN >/dev/null 2>&1; then
      return 0
    fi
    kill "$DEV_SERVER_PID" >/dev/null 2>&1 || true
    wait "$DEV_SERVER_PID" >/dev/null 2>&1 || true
    DEV_SERVER_PID=""
    DEV_SERVER_PORT=""
  done

  echo "control-smoke.sh: could not start a local dev server fixture" >&2
  exit 1
}

run status
SESSION_INSPECT_RESPONSE="$(capture session inspect)"
SESSION_INSPECT_STATE="$(printf '%s' "$SESSION_INSPECT_RESPONSE" | extract_raw result.state)"
SESSION_WORKSPACE_COUNT="$(printf '%s' "$SESSION_INSPECT_RESPONSE" | extract_raw result.current.workspaceCount)"
SESSION_JOURNAL_PATH="$(printf '%s' "$SESSION_INSPECT_RESPONSE" | extract_raw result.journal.path)"
SESSION_SURFACE_TERMINAL_COUNT="$(printf '%s' "$SESSION_INSPECT_RESPONSE" | extract_raw result.surfaces.terminalCount)"
SESSION_SURFACE_WORKSPACE_COUNT="$(printf '%s' "$SESSION_INSPECT_RESPONSE" | extract_raw result.surfaces.workspaceCount)"
SESSION_SURFACE_ISSUE_COUNT="$(printf '%s' "$SESSION_INSPECT_RESPONSE" | extract_raw result.surfaces.issueCount)"
SESSION_SURFACE_CRITICAL_COUNT="$(printf '%s' "$SESSION_INSPECT_RESPONSE" | extract_raw result.surfaces.criticalIssueCount)"
SESSION_SURFACE_WARNING_COUNT="$(printf '%s' "$SESSION_INSPECT_RESPONSE" | extract_raw result.surfaces.warningIssueCount)"
if [ -z "${SESSION_INSPECT_STATE:-}" ] ||
   [ "${SESSION_WORKSPACE_COUNT:-0}" -lt 1 ] ||
   [ -z "${SESSION_JOURNAL_PATH:-}" ] ||
   [ "${SESSION_SURFACE_TERMINAL_COUNT:-0}" -lt 1 ] ||
   [ "${SESSION_SURFACE_WORKSPACE_COUNT:-0}" -lt 1 ] ||
   [ -z "${SESSION_SURFACE_ISSUE_COUNT:-}" ] ||
   [ -z "${SESSION_SURFACE_CRITICAL_COUNT:-}" ] ||
   [ -z "${SESSION_SURFACE_WARNING_COUNT:-}" ]; then
  echo "control-smoke.sh: session inspect did not expose state, current counts, journal path, and structured surface checks" >&2
  exit 1
fi
DIAGNOSTICS_RESPONSE="$(capture diagnostics)"
PERFORMANCE_BUDGET_COUNT="$(printf '%s' "$DIAGNOSTICS_RESPONSE" | extract_raw result.performance.budgets.count)"
MAIN_THREAD_STATUS="$(printf '%s' "$DIAGNOSTICS_RESPONSE" | extract_raw result.performance.mainThread.status)"
PERFORMANCE_REPORT_STATUS="$(printf '%s' "$DIAGNOSTICS_RESPONSE" | extract_raw result.performance.report.status)"
if [ "${PERFORMANCE_BUDGET_COUNT:-0}" -lt 5 ] || [ -z "${MAIN_THREAD_STATUS:-}" ] || [ -z "${PERFORMANCE_REPORT_STATUS:-}" ]; then
  echo "control-smoke.sh: diagnostics did not expose performance budgets, report, and main-thread status" >&2
  exit 1
fi
DIAGNOSTICS_OUTPUT_DIR="$(mktemp -d /tmp/conductor-diagnostics-export.XXXXXX)"
DIAGNOSTICS_EXPORT_RESPONSE="$(capture diagnostics export --output "$DIAGNOSTICS_OUTPUT_DIR")"
DIAGNOSTICS_EXPORT_PATH="$(printf '%s' "$DIAGNOSTICS_EXPORT_RESPONSE" | extract_raw result.path)"
if [ ! -s "$DIAGNOSTICS_EXPORT_PATH/manifest.json" ] || [ ! -s "$DIAGNOSTICS_EXPORT_PATH/summary.redacted.json" ]; then
  echo "control-smoke.sh: diagnostics export did not produce a bundle at $DIAGNOSTICS_EXPORT_PATH" >&2
  exit 1
fi
if ! grep -q '"performance"' "$DIAGNOSTICS_EXPORT_PATH/summary.redacted.json"; then
  echo "control-smoke.sh: diagnostics export summary is missing performance diagnostics" >&2
  exit 1
fi
expect_control_error invalid_params workspace select not-a-workspace
DIAGNOSTICS_AFTER_ERROR="$(capture diagnostics)"
RECENT_CONTROL_ERROR="$(printf '%s' "$DIAGNOSTICS_AFTER_ERROR" | extract_raw result.control.recentErrors.0.code)"
if [ "$RECENT_CONTROL_ERROR" != "invalid_params" ]; then
  echo "control-smoke.sh: diagnostics did not expose recent control error, got '${RECENT_CONTROL_ERROR:-<missing>}'" >&2
  exit 1
fi
run version
NOTIFICATION_TEST_RESPONSE="$(capture notify test --title "Conductor Smoke Notification" --body "Testing system notification delivery." --silent)"
NOTIFICATION_TEST_STATUS="$(printf '%s' "$NOTIFICATION_TEST_RESPONSE" | extract_raw result.status)"
NOTIFICATION_TEST_ADDED="$(printf '%s' "$NOTIFICATION_TEST_RESPONSE" | extract_raw result.addedToNotificationCenter)"
NOTIFICATION_TEST_LAUNCH_SUPPORT="$(printf '%s' "$NOTIFICATION_TEST_RESPONSE" | extract_raw result.launchSupportsSystemNotifications)"
if [ -z "${NOTIFICATION_TEST_STATUS:-}" ] ||
   [ -z "${NOTIFICATION_TEST_ADDED:-}" ] ||
   [ -z "${NOTIFICATION_TEST_LAUNCH_SUPPORT:-}" ]; then
  echo "control-smoke.sh: notify test did not expose delivery status, launch support, and Notification Center result" >&2
  exit 1
fi
if [ "$NOTIFICATION_TEST_ADDED" = "true" ] && [ "$NOTIFICATION_TEST_STATUS" != "delivered" ]; then
  echo "control-smoke.sh: notify test reported Notification Center delivery without delivered status" >&2
  exit 1
fi
if [ "$NOTIFICATION_TEST_LAUNCH_SUPPORT" = "false" ] &&
   { [ "$NOTIFICATION_TEST_STATUS" != "permission_unavailable" ] || [ "$NOTIFICATION_TEST_ADDED" != "false" ]; }; then
  echo "control-smoke.sh: notify test did not explain unsupported debug launch mode" >&2
  exit 1
fi
run workspace list
run workspace create --title "Control Smoke Script"
run workspace rename "Control Smoke Workspace"
run surface list
run surface split --direction right
run surface zoom
run surface focus
DIAGNOSTICS_AFTER_PERF_SAMPLE="$(capture diagnostics)"
PERFORMANCE_SAMPLE_COUNT="$(printf '%s' "$DIAGNOSTICS_AFTER_PERF_SAMPLE" | extract_raw result.performance.samples.recentCount)"
if [ "${PERFORMANCE_SAMPLE_COUNT:-0}" -lt 1 ] ||
   ! recent_performance_budget_seen "$DIAGNOSTICS_AFTER_PERF_SAMPLE" "terminal.tab-switch"; then
  echo "control-smoke.sh: diagnostics did not expose a sampled terminal tab-switch budget" >&2
  exit 1
fi
run terminal cwd
run terminal title
run terminal agent
FOREGROUND_TERMINAL_ID="$(focused_terminal_id)"
FOREGROUND_WORKSPACE_ID="$(terminal_workspace_id "$FOREGROUND_TERMINAL_ID" || true)"
BACKGROUND_TERMINAL_ID="$(first_unfocused_terminal_id "$FOREGROUND_TERMINAL_ID" "$FOREGROUND_WORKSPACE_ID" || true)"
if [ -z "${FOREGROUND_TERMINAL_ID:-}" ] ||
   [ -z "${FOREGROUND_WORKSPACE_ID:-}" ] ||
   [ -z "${BACKGROUND_TERMINAL_ID:-}" ]; then
  echo "control-smoke.sh: expected focused and background terminals after split" >&2
  exit 1
fi
run terminal send --text "sleep 0.4; false" --target "$BACKGROUND_TERMINAL_ID"
run terminal send-key enter --target "$BACKGROUND_TERMINAL_ID"
run surface focus --target "$FOREGROUND_TERMINAL_ID"
COMMAND_FINISHED_NOTIFICATION_ID="$(wait_for_command_finished_notification "$BACKGROUND_TERMINAL_ID" || true)"
if [ -z "${COMMAND_FINISHED_NOTIFICATION_ID:-}" ]; then
  echo "control-smoke.sh: background failed command did not create a commandFinished notification" >&2
  exit 1
fi
COMMAND_FINISHED_FOCUS_RESPONSE="$(capture notify focus "$COMMAND_FINISHED_NOTIFICATION_ID")"
COMMAND_FINISHED_FOCUSED_TERMINAL="$(printf '%s' "$COMMAND_FINISHED_FOCUS_RESPONSE" | extract_raw result.event.terminalID)"
COMMAND_FINISHED_KIND="$(printf '%s' "$COMMAND_FINISHED_FOCUS_RESPONSE" | extract_raw result.event.kind)"
if [ "$COMMAND_FINISHED_FOCUSED_TERMINAL" != "$BACKGROUND_TERMINAL_ID" ] ||
   [ "$COMMAND_FINISHED_KIND" != "commandFinished" ]; then
  echo "control-smoke.sh: commandFinished notification did not focus the originating terminal" >&2
  exit 1
fi
AI_CHANNEL_LIST_RESPONSE="$(capture ai-channel list)"
AI_CHANNEL_COUNT="$(printf '%s' "$AI_CHANNEL_LIST_RESPONSE" | extract_raw result.count)"
if [ "${AI_CHANNEL_COUNT:-0}" -lt 3 ]; then
  echo "control-smoke.sh: ai-channel list did not expose built-in channels" >&2
  exit 1
fi
AI_CHANNEL_CONFIGURE_RESPONSE="$(capture ai-channel configure local-smoke --name "Local Smoke" --kind openai-compatible --model qwen-smoke --endpoint http://127.0.0.1:11434/v1 --priority 150 --env OPENAI_API_KEY=smoke-secret)"
AI_CHANNEL_CONFIGURED_ID="$(printf '%s' "$AI_CHANNEL_CONFIGURE_RESPONSE" | extract_raw result.channel.id)"
AI_CHANNEL_CONFIGURED_HEALTH="$(printf '%s' "$AI_CHANNEL_CONFIGURE_RESPONSE" | extract_raw result.channel.health)"
AI_CHANNEL_CONFIGURED_KEYS="$(printf '%s' "$AI_CHANNEL_CONFIGURE_RESPONSE" | extract_raw result.channel.environmentKeys.0)"
if [ "$AI_CHANNEL_CONFIGURED_ID" != "local-smoke" ] || [ "$AI_CHANNEL_CONFIGURED_HEALTH" != "ready" ] || [ "$AI_CHANNEL_CONFIGURED_KEYS" != "OPENAI_API_KEY" ]; then
  echo "control-smoke.sh: ai-channel configure did not persist a ready custom channel" >&2
  exit 1
fi
AI_CHANNEL_DEFAULT_RESPONSE="$(capture ai-channel set-default local-smoke)"
AI_CHANNEL_DEFAULT_ID="$(printf '%s' "$AI_CHANNEL_DEFAULT_RESPONSE" | extract_raw result.default.id)"
if [ "$AI_CHANNEL_DEFAULT_ID" != "local-smoke" ]; then
  echo "control-smoke.sh: ai-channel set-default did not select the configured channel" >&2
  exit 1
fi
AI_CHANNEL_SET_RESPONSE="$(capture terminal channel set codex --model gpt-5 --env CONDUCTOR_TEST_AI_CHANNEL=smoke)"
AI_CHANNEL_ID="$(printf '%s' "$AI_CHANNEL_SET_RESPONSE" | extract_raw result.binding.channelID)"
AI_CHANNEL_MODEL="$(printf '%s' "$AI_CHANNEL_SET_RESPONSE" | extract_raw result.binding.model)"
AI_CHANNEL_REQUIRES_NEW_SURFACE="$(printf '%s' "$AI_CHANNEL_SET_RESPONSE" | extract_raw result.requiresNewSurface)"
if [ "$AI_CHANNEL_ID" != "codex" ] || [ "$AI_CHANNEL_MODEL" != "gpt-5" ]; then
  echo "control-smoke.sh: terminal channel set did not persist the expected binding" >&2
  exit 1
fi
if [ -z "${AI_CHANNEL_REQUIRES_NEW_SURFACE:-}" ]; then
  echo "control-smoke.sh: terminal channel set did not report whether a new surface is required" >&2
  exit 1
fi
AI_CHANNEL_GET_RESPONSE="$(capture terminal channel get)"
AI_CHANNEL_GET_ID="$(printf '%s' "$AI_CHANNEL_GET_RESPONSE" | extract_raw result.binding.channelID)"
if [ "$AI_CHANNEL_GET_ID" != "codex" ]; then
  echo "control-smoke.sh: terminal channel get did not return the persisted binding" >&2
  exit 1
fi
AI_CHANNEL_CLEAR_RESPONSE="$(capture terminal channel clear)"
AI_CHANNEL_INHERITED_ID="$(printf '%s' "$AI_CHANNEL_CLEAR_RESPONSE" | extract_raw result.effectiveBinding.channelID)"
if [ "$AI_CHANNEL_INHERITED_ID" != "local-smoke" ]; then
  echo "control-smoke.sh: terminal channel clear did not inherit the global default channel" >&2
  exit 1
fi
DIAGNOSTICS_AFTER_AI_CHANNEL="$(capture diagnostics)"
AI_CHANNEL_DIAGNOSTIC_ID="$(printf '%s' "$DIAGNOSTICS_AFTER_AI_CHANNEL" | extract_raw result.aiChannels.focusedTerminal.effectiveBinding.channelID)"
if [ "$AI_CHANNEL_DIAGNOSTIC_ID" != "local-smoke" ]; then
  echo "control-smoke.sh: diagnostics did not expose the focused terminal effective channel binding" >&2
  exit 1
fi
run terminal send --text "printf 'conductor-control-smoke\\n'\n"
run terminal send-key enter
run terminal visible-text
run terminal sample-scroll
DIAGNOSTICS_AFTER_SCROLL_SAMPLE="$(capture diagnostics)"
if ! recent_performance_budget_seen "$DIAGNOSTICS_AFTER_SCROLL_SAMPLE" "terminal.scroll-frame"; then
  echo "control-smoke.sh: diagnostics did not expose a sampled terminal scroll budget" >&2
  exit 1
fi

FIXTURE_PATH="$SCRIPT_DIR/fixtures/browser-automation.html"
FIXTURE_URL="file://${FIXTURE_PATH// /%20}"
WORKSPACE_METADATA_EXPECTED_WEB_URL="$FIXTURE_URL"
FILE_FIXTURE_DIR="$(mktemp -d /tmp/conductor-file-fixture.XXXXXX)"
FILE_FIXTURE_PATH="$FILE_FIXTURE_DIR/control-file.txt"
DOWNLOAD_FIXTURE_PATH="$FILE_FIXTURE_DIR/conductor-browser-download-fixture.bin"
printf 'Conductor file smoke\n' >"$FILE_FIXTURE_PATH"
printf 'Conductor dev server smoke\n' >"$FILE_FIXTURE_DIR/index.html"
printf 'Conductor browser download fixture\n' >"$DOWNLOAD_FIXTURE_PATH"
start_dev_server_fixture
run browser open "$FIXTURE_URL"
sleep 1
capture browser wait load --timeout 10 >/dev/null
capture browser wait url "browser-automation.html" --timeout 5 >/dev/null
capture browser wait title "Conductor Browser Fixture" --timeout 5 >/dev/null
capture browser wait idle --timeout 5 >/dev/null
capture browser wait hidden "#hidden-marker" --timeout 5 >/dev/null
capture browser wait gone "#fixture-never-attached" --timeout 5 >/dev/null
BROWSER_SURFACE_ID="$(browser_tab_id_for_url "$FIXTURE_URL" || true)"
if [ -z "${BROWSER_SURFACE_ID:-}" ]; then
  echo "control-smoke.sh: could not resolve browser surface ID for focus smoke" >&2
  exit 1
fi
BROWSER_FOCUS_RESPONSE="$(capture surface focus --web-tab "$BROWSER_SURFACE_ID")"
BROWSER_FOCUS_TYPE="$(printf '%s' "$BROWSER_FOCUS_RESPONSE" | extract_raw result.type)"
BROWSER_FOCUS_ID="$(printf '%s' "$BROWSER_FOCUS_RESPONSE" | extract_raw result.webTabID)"
if [ "$BROWSER_FOCUS_TYPE" != "browser" ] || [ "$BROWSER_FOCUS_ID" != "$BROWSER_SURFACE_ID" ]; then
  echo "control-smoke.sh: surface focus did not focus browser surface" >&2
  exit 1
fi
run browser reload
sleep 1
capture browser wait load --timeout 10 >/dev/null
capture browser wait "#late-ready" --timeout 10 >/dev/null

SNAPSHOT_RESPONSE="$(capture browser snapshot)"
SNAPSHOT_TEXT="$(printf '%s' "$SNAPSHOT_RESPONSE" | extract_raw result.text)"
assert_contains "$SNAPSHOT_TEXT" "Conductor Browser Fixture" "browser snapshot text"
assert_contains "$SNAPSHOT_RESPONSE" "conductor fixture console error" "browser runtime event snapshot"
SNAPSHOT_FRAME_ID="$(printf '%s' "$SNAPSHOT_RESPONSE" | extract_raw result.frames.0.id)"
SNAPSHOT_SANDBOX_FRAME_ID="$(printf '%s' "$SNAPSHOT_RESPONSE" | extract_raw result.frames.1.id)"
SNAPSHOT_FRAME_TEXT="$(printf '%s' "$SNAPSHOT_RESPONSE" | extract_raw result.frames.0.text)"
SNAPSHOT_FRAME_ACCESSIBLE="$(printf '%s' "$SNAPSHOT_RESPONSE" | extract_raw result.frames.0.accessible)"
SNAPSHOT_SANDBOX_FRAME_ACCESSIBLE="$(printf '%s' "$SNAPSHOT_RESPONSE" | extract_raw result.frames.1.accessible)"
SNAPSHOT_SANDBOX_FRAME_REASON="$(printf '%s' "$SNAPSHOT_RESPONSE" | extract_raw result.frames.1.reason)"
assert_contains "$SNAPSHOT_FRAME_TEXT" "Same-origin frame fixture ready" "browser frame snapshot text"
if [ -z "${SNAPSHOT_FRAME_ID:-}" ] ||
   [ -z "${SNAPSHOT_SANDBOX_FRAME_ID:-}" ] ||
   [ "$SNAPSHOT_FRAME_ACCESSIBLE" != "true" ] ||
   [ "$SNAPSHOT_SANDBOX_FRAME_ACCESSIBLE" != "false" ] ||
   [ -z "${SNAPSHOT_SANDBOX_FRAME_REASON:-}" ]; then
  echo "control-smoke.sh: browser snapshot did not explain accessible and inaccessible frames" >&2
  echo "$SNAPSHOT_RESPONSE" >&2
  exit 1
fi
capture browser fill "frame-0 >> #frame-query" "Nested frame smoke" >/dev/null
capture browser click "frame-0 >> #frame-run" >/dev/null
capture browser wait text "frame-0 >> Frame completed: Nested frame smoke" --timeout 5 >/dev/null
FRAME_FIND_RESPONSE="$(capture browser find "Frame completed: Nested frame smoke")"
FRAME_FIND_MATCHES="$(printf '%s' "$FRAME_FIND_RESPONSE" | extract_raw result.matches)"
FRAME_FIND_SUMMARY="$(printf '%s' "$FRAME_FIND_RESPONSE" | extract_raw result.result)"
if [ "${FRAME_FIND_MATCHES:-0}" -lt 1 ] || [[ "$FRAME_FIND_SUMMARY" != *"frame-0"* ]]; then
  echo "control-smoke.sh: browser find did not include same-origin frame matches" >&2
  echo "$FRAME_FIND_RESPONSE" >&2
  exit 1
fi
FRAME_EVALUATE_RESPONSE="$(capture browser evaluate --frame frame-0 "document.getElementById('frame-output').textContent")"
FRAME_EVALUATE_RESULT="$(printf '%s' "$FRAME_EVALUATE_RESPONSE" | extract_raw result.result)"
assert_contains "$FRAME_EVALUATE_RESULT" "Frame completed: Nested frame smoke" "browser frame evaluate result"
BROWSER_RUNTIME_EVENT_COUNT="$(browser_runtime_event_count_for_tab "$BROWSER_SURFACE_ID" || true)"
if [ "${BROWSER_RUNTIME_EVENT_COUNT:-0}" -lt 1 ]; then
  echo "control-smoke.sh: browser surface did not expose runtime event count" >&2
  exit 1
fi
SESSION_INSPECT_AFTER_RUNTIME="$(capture session inspect)"
RUNTIME_ISSUE_IMPACT="$(session_surface_issue_field web_runtime_error impact "$SESSION_INSPECT_AFTER_RUNTIME" || true)"
RUNTIME_ISSUE_ACTION_KIND="$(session_surface_issue_field web_runtime_error primaryAction.kind "$SESSION_INSPECT_AFTER_RUNTIME" || true)"
RUNTIME_ISSUE_ACTION_TITLE="$(session_surface_issue_field web_runtime_error primaryAction.title "$SESSION_INSPECT_AFTER_RUNTIME" || true)"
if [ -z "${RUNTIME_ISSUE_IMPACT:-}" ] ||
   [ -z "${RUNTIME_ISSUE_ACTION_KIND:-}" ] ||
   [ -z "${RUNTIME_ISSUE_ACTION_TITLE:-}" ]; then
  echo "control-smoke.sh: runtime recovery issue did not expose impact and primary action" >&2
  echo "$SESSION_INSPECT_AFTER_RUNTIME" >&2
  exit 1
fi

capture browser fill "#smoke-query" "Conductor browser smoke" >/dev/null
capture browser press Enter --element "#smoke-query" >/dev/null
capture browser wait text "Completed: Conductor browser smoke" --timeout 5 >/dev/null

capture browser fill "#smoke-query" "Clicked fixture smoke" >/dev/null
capture browser click "#smoke-run" >/dev/null
capture browser wait text "Completed: Clicked fixture smoke" --timeout 5 >/dev/null

FIND_RESPONSE="$(capture browser find "Completed: Clicked fixture smoke")"
FIND_MATCHES="$(printf '%s' "$FIND_RESPONSE" | extract_raw result.matches)"
if [ "${FIND_MATCHES:-0}" -lt 1 ]; then
  echo "control-smoke.sh: browser find did not report a match" >&2
  exit 1
fi

EVALUATE_RESPONSE="$(capture browser evaluate "document.getElementById('smoke-output').textContent")"
EVALUATE_RESULT="$(printf '%s' "$EVALUATE_RESPONSE" | extract_raw result.result)"
assert_contains "$EVALUATE_RESULT" "Completed: Clicked fixture smoke" "browser evaluate result"

expect_error_code selector_not_found browser click "#missing-control"
expect_error_code invalid_selector browser click "["
expect_error_code snapshot_ref_missing browser click button-42
expect_error_code not_editable browser fill "main" "not editable"
expect_error_code text_not_found browser find "Never appears in fixture"
expect_error_code script_error browser evaluate "(() => { throw new Error('fixture boom') })()"
expect_error_code promise_unsupported browser evaluate "Promise.resolve('later')"
expect_error_code timeout browser wait text "Still not here" --timeout 0.2
expect_error_code timeout browser wait url "https://example.invalid/not-current" --timeout 0.2
expect_error_code frame_inaccessible browser click "frame-1 >> button"
expect_error_code frame_inaccessible browser evaluate --frame frame-1 "document.body.innerText"

SCREENSHOT_RESPONSE="$(capture browser screenshot)"
SCREENSHOT_PATH="$(printf '%s' "$SCREENSHOT_RESPONSE" | extract_raw result.path)"
if [ ! -s "$SCREENSHOT_PATH" ]; then
  echo "control-smoke.sh: browser screenshot did not produce a file at $SCREENSHOT_PATH" >&2
  exit 1
fi
capture browser navigate "http://localhost:$DEV_SERVER_PORT" --web-tab "$BROWSER_SURFACE_ID" >/dev/null
capture browser wait load --timeout 10 --web-tab "$BROWSER_SURFACE_ID" >/dev/null
BROWSER_RUNTIME_EVENT_COUNT_AFTER_NAVIGATE="$(browser_runtime_event_count_for_tab "$BROWSER_SURFACE_ID" || true)"
if [ "${BROWSER_RUNTIME_EVENT_COUNT_AFTER_NAVIGATE:-0}" -ne 0 ]; then
  echo "control-smoke.sh: browser runtime events were not cleared after navigation" >&2
  echo "  count=${BROWSER_RUNTIME_EVENT_COUNT_AFTER_NAVIGATE:-<missing>}" >&2
  exit 1
fi
WORKSPACE_METADATA_EXPECTED_WEB_URL="http://localhost:$DEV_SERVER_PORT"
run browser stop
DOWNLOAD_URL="http://localhost:$DEV_SERVER_PORT/$(basename "$DOWNLOAD_FIXTURE_PATH")"
run browser open "$DOWNLOAD_URL"
sleep 1
DOWNLOAD_SURFACE_ID="$(browser_tab_id_for_url "$DOWNLOAD_URL" || true)"
if [ -z "${DOWNLOAD_SURFACE_ID:-}" ]; then
  echo "control-smoke.sh: could not resolve browser surface ID for download smoke" >&2
  exit 1
fi
if ! wait_for_browser_download_finished "$DOWNLOAD_SURFACE_ID"; then
  exit 1
fi
DOWNLOAD_PHASE="$(browser_download_field_for_tab "$DOWNLOAD_SURFACE_ID" phase || true)"
DOWNLOAD_DESTINATION="$(browser_download_field_for_tab "$DOWNLOAD_SURFACE_ID" destinationPath || true)"
DOWNLOAD_FILENAME="$(browser_download_field_for_tab "$DOWNLOAD_SURFACE_ID" filename || true)"
if [ "$DOWNLOAD_PHASE" != "finished" ] ||
   [[ "$DOWNLOAD_FILENAME" != conductor-browser-download-fixture* ]] ||
   [ ! -s "$DOWNLOAD_DESTINATION" ]; then
  echo "control-smoke.sh: browser download state was not complete or destination was missing" >&2
  echo "  phase=${DOWNLOAD_PHASE:-<missing>}" >&2
  echo "  filename=${DOWNLOAD_FILENAME:-<missing>}" >&2
  echo "  destination=${DOWNLOAD_DESTINATION:-<missing>}" >&2
  exit 1
fi
rm -f "$DOWNLOAD_DESTINATION"
run browser open "http://localhost:$DEV_SERVER_PORT"
capture browser wait load --timeout 10 >/dev/null
run file open "$FILE_FIXTURE_PATH"
FILE_FOCUS_RESPONSE="$(capture surface focus --file-tab "$FILE_FIXTURE_PATH")"
FILE_FOCUS_TYPE="$(printf '%s' "$FILE_FOCUS_RESPONSE" | extract_raw result.type)"
FILE_FOCUS_ID="$(printf '%s' "$FILE_FOCUS_RESPONSE" | extract_raw result.fileTabID)"
if [ "$FILE_FOCUS_TYPE" != "file" ] || [ "$FILE_FOCUS_ID" != "$FILE_FIXTURE_PATH" ]; then
  echo "control-smoke.sh: surface focus did not focus file surface" >&2
  exit 1
fi
FILE_SNAPSHOT_RESPONSE="$(capture file snapshot --text)"
FILE_SNAPSHOT_TEXT="$(printf '%s' "$FILE_SNAPSHOT_RESPONSE" | extract_raw result.file.text.value)"
FILE_BUFFER_AVAILABLE="$(printf '%s' "$FILE_SNAPSHOT_RESPONSE" | extract_raw result.file.buffer.available)"
assert_contains "$FILE_SNAPSHOT_TEXT" "Conductor file smoke" "file snapshot text"
if [ "$FILE_BUFFER_AVAILABLE" != "true" ]; then
  echo "control-smoke.sh: file snapshot did not expose a synchronized editor buffer" >&2
  echo "$FILE_SNAPSHOT_RESPONSE" >&2
  exit 1
fi
capture file save "$FILE_FIXTURE_PATH" --text "Conductor file smoke updated" >/dev/null
if ! grep -q "Conductor file smoke updated" "$FILE_FIXTURE_PATH"; then
  echo "control-smoke.sh: file save did not update $FILE_FIXTURE_PATH" >&2
  exit 1
fi
BUFFERED_SAVE_RESPONSE="$(capture file save "$FILE_FIXTURE_PATH")"
BUFFERED_SAVE_MODE="$(printf '%s' "$BUFFERED_SAVE_RESPONSE" | extract_raw result.mode)"
BUFFERED_SAVE_REQUESTED="$(printf '%s' "$BUFFERED_SAVE_RESPONSE" | extract_raw result.saveRequested)"
BUFFERED_SAVE_REVISION="$(printf '%s' "$BUFFERED_SAVE_RESPONSE" | extract_raw result.file.buffer.savedRevision)"
if [ "$BUFFERED_SAVE_MODE" != "buffered-editor-save" ] ||
   [ "$BUFFERED_SAVE_REQUESTED" != "false" ] ||
   [ "${BUFFERED_SAVE_REVISION:-0}" -lt 1 ]; then
  echo "control-smoke.sh: file save without --text did not synchronously save the editor buffer" >&2
  echo "$BUFFERED_SAVE_RESPONSE" >&2
  exit 1
fi
run file reveal "$FILE_FIXTURE_PATH"
run file snapshot --target "$FILE_FIXTURE_PATH"
SELECTED_WORKSPACE_ID="$(capture status | extract_raw result.selectedWorkspaceID)"
WORKSPACE_METADATA_RESPONSE=""
WORKSPACE_METADATA_DEV_SERVER_URL=""
WORKSPACE_METADATA_DEV_SERVER_LABEL=""
for _ in 1 2 3 4; do
  WORKSPACE_METADATA_RESPONSE="$(capture workspace metadata --workspace "$SELECTED_WORKSPACE_ID")"
  for index in $(seq 0 20); do
    CANDIDATE_DEV_SERVER_URL="$(printf '%s' "$WORKSPACE_METADATA_RESPONSE" | extract_raw "result.workspaces.0.devServers.$index.url" 2>/dev/null || true)"
    CANDIDATE_DEV_SERVER_LABEL="$(printf '%s' "$WORKSPACE_METADATA_RESPONSE" | extract_raw "result.workspaces.0.devServers.$index.label" 2>/dev/null || true)"
    if [ "$CANDIDATE_DEV_SERVER_URL" = "http://localhost:$DEV_SERVER_PORT" ]; then
      WORKSPACE_METADATA_DEV_SERVER_URL="$CANDIDATE_DEV_SERVER_URL"
      WORKSPACE_METADATA_DEV_SERVER_LABEL="$CANDIDATE_DEV_SERVER_LABEL"
      break
    fi
  done
  if [ -n "$WORKSPACE_METADATA_DEV_SERVER_URL" ]; then
    break
  fi
  sleep 0.5
done
WORKSPACE_METADATA_COUNT="$(printf '%s' "$WORKSPACE_METADATA_RESPONSE" | extract_raw result.workspaceCount)"
WORKSPACE_METADATA_TERMINALS="$(printf '%s' "$WORKSPACE_METADATA_RESPONSE" | extract_raw result.workspaces.0.counts.terminalCount)"
WORKSPACE_METADATA_HEALTH="$(printf '%s' "$WORKSPACE_METADATA_RESPONSE" | extract_raw result.workspaces.0.health)"
WORKSPACE_METADATA_TERMINAL_ID="$(printf '%s' "$WORKSPACE_METADATA_RESPONSE" | extract_raw result.workspaces.0.terminals.0.id)"
WORKSPACE_METADATA_FILE_PATH="$(printf '%s' "$WORKSPACE_METADATA_RESPONSE" | extract_raw result.workspaces.0.files.0.path)"
WORKSPACE_METADATA_WEB_URL=""
for index in $(seq 0 20); do
  CANDIDATE_WEB_URL="$(printf '%s' "$WORKSPACE_METADATA_RESPONSE" | extract_raw "result.workspaces.0.webTabs.$index.url" 2>/dev/null || true)"
  if [ "$CANDIDATE_WEB_URL" = "$WORKSPACE_METADATA_EXPECTED_WEB_URL" ] ||
     [ "$CANDIDATE_WEB_URL" = "$WORKSPACE_METADATA_EXPECTED_WEB_URL/" ]; then
    WORKSPACE_METADATA_WEB_URL="$WORKSPACE_METADATA_EXPECTED_WEB_URL"
    break
  fi
done
if [ "${WORKSPACE_METADATA_COUNT:-0}" -ne 1 ] || [ "${WORKSPACE_METADATA_TERMINALS:-0}" -lt 1 ] || [ -z "${WORKSPACE_METADATA_HEALTH:-}" ]; then
  echo "control-smoke.sh: workspace metadata did not expose selected workspace counts and health" >&2
  exit 1
fi
if [ -z "${WORKSPACE_METADATA_TERMINAL_ID:-}" ] ||
   [ "$WORKSPACE_METADATA_FILE_PATH" != "$FILE_FIXTURE_PATH" ] ||
   [ "$WORKSPACE_METADATA_WEB_URL" != "$WORKSPACE_METADATA_EXPECTED_WEB_URL" ]; then
  echo "control-smoke.sh: workspace metadata did not expose terminal/file/web summaries" >&2
  echo "  terminalID=${WORKSPACE_METADATA_TERMINAL_ID:-<missing>}" >&2
  echo "  filePath=${WORKSPACE_METADATA_FILE_PATH:-<missing>}" >&2
  echo "  expectedFilePath=$FILE_FIXTURE_PATH" >&2
  echo "  webURL=${WORKSPACE_METADATA_WEB_URL:-<missing>}" >&2
  echo "  expectedWebURL=$WORKSPACE_METADATA_EXPECTED_WEB_URL" >&2
  echo "$WORKSPACE_METADATA_RESPONSE" >&2
  exit 1
fi
if [ "$WORKSPACE_METADATA_DEV_SERVER_URL" != "http://localhost:$DEV_SERVER_PORT" ] ||
   [[ "$WORKSPACE_METADATA_DEV_SERVER_LABEL" != *":$DEV_SERVER_PORT" ]]; then
  echo "control-smoke.sh: workspace metadata did not expose dev server summaries" >&2
  echo "$WORKSPACE_METADATA_RESPONSE" >&2
  exit 1
fi
SECOND_FILE_FIXTURE_PATH="$FILE_FIXTURE_DIR/secondary-file.txt"
printf 'Conductor secondary workspace file smoke\n' >"$SECOND_FILE_FIXTURE_PATH"
SECOND_WORKSPACE_RESPONSE="$(capture workspace create --title "Control Smoke Secondary")"
SECOND_WORKSPACE_ID="$(printf '%s' "$SECOND_WORKSPACE_RESPONSE" | extract_raw result.workspaceID)"
if [ -z "${SECOND_WORKSPACE_ID:-}" ]; then
  echo "control-smoke.sh: secondary workspace create did not return a workspaceID" >&2
  exit 1
fi
SECOND_TERMINAL_ID="$(focused_terminal_id)"
if [ -z "${SECOND_TERMINAL_ID:-}" ]; then
  echo "control-smoke.sh: expected a focused terminal in the secondary workspace" >&2
  exit 1
fi
run browser open "$FIXTURE_URL"
capture browser wait load --timeout 10 >/dev/null
run file open "$SECOND_FILE_FIXTURE_PATH"
run workspace select "$SELECTED_WORKSPACE_ID"
SECOND_METADATA_RESPONSE="$(capture workspace metadata --workspace "$SECOND_WORKSPACE_ID")"
SECOND_METADATA_FILE_PATH="$(printf '%s' "$SECOND_METADATA_RESPONSE" | extract_raw result.workspaces.0.files.0.path)"
SECOND_METADATA_WEB_URL="$(printf '%s' "$SECOND_METADATA_RESPONSE" | extract_raw result.workspaces.0.webTabs.0.url)"
if [ "$SECOND_METADATA_FILE_PATH" != "$SECOND_FILE_FIXTURE_PATH" ] ||
   [ "$SECOND_METADATA_WEB_URL" != "$FIXTURE_URL" ]; then
  echo "control-smoke.sh: workspace metadata did not preserve non-selected workspace file/web summaries" >&2
  exit 1
fi
PRIMARY_ATTENTION_RESPONSE="$(capture notify "Primary attention smoke" --body "Jump latest should prefer the selected workspace." --workspace "$SELECTED_WORKSPACE_ID" --terminal "$FOREGROUND_TERMINAL_ID")"
PRIMARY_ATTENTION_ID="$(printf '%s' "$PRIMARY_ATTENTION_RESPONSE" | extract_raw result.notificationID)"
sleep 0.15
SECONDARY_ATTENTION_RESPONSE="$(capture notify "Secondary attention smoke" --body "Jump latest should fall back globally when the selected workspace is quiet." --workspace "$SECOND_WORKSPACE_ID" --terminal "$SECOND_TERMINAL_ID")"
SECONDARY_ATTENTION_ID="$(printf '%s' "$SECONDARY_ATTENTION_RESPONSE" | extract_raw result.notificationID)"
if [ -z "${PRIMARY_ATTENTION_ID:-}" ] || [ -z "${SECONDARY_ATTENTION_ID:-}" ]; then
  echo "control-smoke.sh: targeted attention notifications did not return IDs" >&2
  exit 1
fi
JUMP_CURRENT_RESPONSE="$(capture command run jumpLatestUnreadAttention)"
JUMP_CURRENT_PERFORMED="$(printf '%s' "$JUMP_CURRENT_RESPONSE" | extract_raw result.performed)"
JUMP_CURRENT_FOCUS="$(focused_terminal_id)"
PRIMARY_ATTENTION_READ="$(notification_field_by_id "$PRIMARY_ATTENTION_ID" read)"
if [ "$JUMP_CURRENT_PERFORMED" != "true" ] ||
   [ "$JUMP_CURRENT_FOCUS" != "$FOREGROUND_TERMINAL_ID" ] ||
   [ "$PRIMARY_ATTENTION_READ" != "true" ]; then
  echo "control-smoke.sh: jumpLatestUnreadAttention did not prefer and mark the selected workspace attention target" >&2
  echo "$JUMP_CURRENT_RESPONSE" >&2
  exit 1
fi
JUMP_GLOBAL_RESPONSE="$(capture command run jumpLatestUnreadAttention)"
JUMP_GLOBAL_PERFORMED="$(printf '%s' "$JUMP_GLOBAL_RESPONSE" | extract_raw result.performed)"
JUMP_GLOBAL_FOCUS="$(focused_terminal_id)"
JUMP_GLOBAL_WORKSPACE="$(terminal_workspace_id "$JUMP_GLOBAL_FOCUS" || true)"
SECONDARY_ATTENTION_READ="$(notification_field_by_id "$SECONDARY_ATTENTION_ID" read)"
if [ "$JUMP_GLOBAL_PERFORMED" != "true" ] ||
   [ "$JUMP_GLOBAL_FOCUS" != "$SECOND_TERMINAL_ID" ] ||
   [ "$JUMP_GLOBAL_WORKSPACE" != "$SECOND_WORKSPACE_ID" ] ||
   [ "$SECONDARY_ATTENTION_READ" != "true" ]; then
  echo "control-smoke.sh: jumpLatestUnreadAttention did not fall back to the latest global attention target" >&2
  echo "$JUMP_GLOBAL_RESPONSE" >&2
  exit 1
fi
run workspace select "$SELECTED_WORKSPACE_ID"
MARK_READ_RESPONSE="$(capture notify "Workspace read smoke" --body "Mark current workspace read should not move focus." --workspace "$SELECTED_WORKSPACE_ID" --terminal "$FOREGROUND_TERMINAL_ID")"
MARK_READ_ID="$(printf '%s' "$MARK_READ_RESPONSE" | extract_raw result.notificationID)"
MARK_COMMAND_RESPONSE="$(capture command run markCurrentWorkspaceAttentionRead)"
MARK_COMMAND_PERFORMED="$(printf '%s' "$MARK_COMMAND_RESPONSE" | extract_raw result.performed)"
MARKED_READ="$(notification_field_by_id "$MARK_READ_ID" read)"
if [ "$MARK_COMMAND_PERFORMED" != "true" ] || [ "$MARKED_READ" != "true" ]; then
  echo "control-smoke.sh: markCurrentWorkspaceAttentionRead did not mark current workspace notifications read" >&2
  echo "$MARK_COMMAND_RESPONSE" >&2
  exit 1
fi
expect_control_error_detail file_not_found path "$FILE_FIXTURE_DIR/missing-file.txt" file open "$FILE_FIXTURE_DIR/missing-file.txt"
expect_control_error_detail file_is_directory path "$FILE_FIXTURE_DIR" file open "$FILE_FIXTURE_DIR"
expect_control_error_detail file_not_found path "$FILE_FIXTURE_DIR/missing-reveal.txt" file reveal "$FILE_FIXTURE_DIR/missing-reveal.txt"
expect_control_error_detail file_is_directory path "$FILE_FIXTURE_DIR" file save "$FILE_FIXTURE_DIR" --text "directory write should fail"
expect_control_error_detail file_parent_not_found path "$FILE_FIXTURE_DIR/missing-parent" file save "$FILE_FIXTURE_DIR/missing-parent/new.txt" --text "parent write should fail"
expect_control_error target_not_found file save "$FILE_FIXTURE_DIR/unopened-no-text.txt"
COMMAND_LIST_RESPONSE="$(capture command list)"
COMMAND_LIST_TITLE="$(printf '%s' "$COMMAND_LIST_RESPONSE" | extract_raw result.commands.0.title)"
COMMAND_LIST_CATEGORY="$(printf '%s' "$COMMAND_LIST_RESPONSE" | extract_raw result.commands.0.category)"
COMMAND_LIST_DESCRIPTION="$(printf '%s' "$COMMAND_LIST_RESPONSE" | extract_raw result.commands.0.description)"
COMMAND_LIST_PROTOCOL_METHOD="$(printf '%s' "$COMMAND_LIST_RESPONSE" | extract_raw result.commands.0.protocolMethod)"
COMMAND_LIST_SYSTEM_IMAGE="$(printf '%s' "$COMMAND_LIST_RESPONSE" | extract_raw result.commands.0.systemImage)"
COMMAND_LIST_NEW_WORKSPACE_METHOD="$(command_field_by_id "$COMMAND_LIST_RESPONSE" "newWorkspace" "protocolMethod")"
COMMAND_LIST_WEB_BACK_CATALOG_ID="$(command_field_by_id "$COMMAND_LIST_RESPONSE" "goBackSelectedWebTab" "catalogID")"
COMMAND_LIST_WEB_FORWARD_CATALOG_ID="$(command_field_by_id "$COMMAND_LIST_RESPONSE" "goForwardSelectedWebTab" "catalogID")"
COMMAND_LIST_WEB_BACK_METHOD="$(command_field_by_id "$COMMAND_LIST_RESPONSE" "goBackSelectedWebTab" "protocolMethod")"
COMMAND_LIST_WEB_FORWARD_METHOD="$(command_field_by_id "$COMMAND_LIST_RESPONSE" "goForwardSelectedWebTab" "protocolMethod")"
COMMAND_LIST_FILE_OPEN_CATALOG_ID="$(command_field_by_id "$COMMAND_LIST_RESPONSE" "openSelectedFileExternally" "catalogID")"
COMMAND_LIST_FILE_REVEAL_CATALOG_ID="$(command_field_by_id "$COMMAND_LIST_RESPONSE" "revealSelectedFileInFinder" "catalogID")"
COMMAND_LIST_FILE_OPEN_METHOD="$(command_field_by_id "$COMMAND_LIST_RESPONSE" "openSelectedFileExternally" "protocolMethod")"
COMMAND_LIST_FILE_REVEAL_METHOD="$(command_field_by_id "$COMMAND_LIST_RESPONSE" "revealSelectedFileInFinder" "protocolMethod")"
COMMAND_LIST_DUPLICATE_WORKSPACE_CATALOG_ID="$(command_field_by_id "$COMMAND_LIST_RESPONSE" "duplicateWorkspace" "catalogID")"
COMMAND_LIST_CLOSE_OTHER_WORKSPACES_CATALOG_ID="$(command_field_by_id "$COMMAND_LIST_RESPONSE" "closeOtherWorkspaces" "catalogID")"
COMMAND_LIST_CLOSE_WORKSPACES_RIGHT_CATALOG_ID="$(command_field_by_id "$COMMAND_LIST_RESPONSE" "closeWorkspacesToRight" "catalogID")"
COMMAND_LIST_CLOSE_CURRENT_WORKSPACE_CATALOG_ID="$(command_field_by_id "$COMMAND_LIST_RESPONSE" "closeCurrentWorkspace" "catalogID")"
COMMAND_LIST_WORKSPACE_ROOT_CATALOG_ID="$(command_field_by_id "$COMMAND_LIST_RESPONSE" "openCurrentWorkspaceRoot" "catalogID")"
COMMAND_LIST_WORKSPACE_SERVICE_CATALOG_ID="$(command_field_by_id "$COMMAND_LIST_RESPONSE" "openCurrentWorkspaceFirstService" "catalogID")"
COMMAND_LIST_RENAME_WORKSPACE_CATALOG_ID="$(command_field_by_id "$COMMAND_LIST_RESPONSE" "renameCurrentWorkspace" "catalogID")"
COMMAND_LIST_DUPLICATE_WORKSPACE_METHOD="$(command_field_by_id "$COMMAND_LIST_RESPONSE" "duplicateWorkspace" "protocolMethod")"
COMMAND_LIST_CLOSE_OTHER_WORKSPACES_METHOD="$(command_field_by_id "$COMMAND_LIST_RESPONSE" "closeOtherWorkspaces" "protocolMethod")"
COMMAND_LIST_CLOSE_WORKSPACES_RIGHT_METHOD="$(command_field_by_id "$COMMAND_LIST_RESPONSE" "closeWorkspacesToRight" "protocolMethod")"
COMMAND_LIST_CLOSE_CURRENT_WORKSPACE_METHOD="$(command_field_by_id "$COMMAND_LIST_RESPONSE" "closeCurrentWorkspace" "protocolMethod")"
COMMAND_LIST_WORKSPACE_ROOT_METHOD="$(command_field_by_id "$COMMAND_LIST_RESPONSE" "openCurrentWorkspaceRoot" "protocolMethod")"
COMMAND_LIST_WORKSPACE_SERVICE_METHOD="$(command_field_by_id "$COMMAND_LIST_RESPONSE" "openCurrentWorkspaceFirstService" "protocolMethod")"
COMMAND_LIST_RENAME_WORKSPACE_METHOD="$(command_field_by_id "$COMMAND_LIST_RESPONSE" "renameCurrentWorkspace" "protocolMethod")"
COMMAND_LIST_RECENT_RANK="$(command_field_by_id "$COMMAND_LIST_RESPONSE" "markCurrentWorkspaceAttentionRead" "ranking.recentRank")"
COMMAND_LIST_RECENT_FLAG="$(command_field_by_id "$COMMAND_LIST_RESPONSE" "markCurrentWorkspaceAttentionRead" "ranking.recent")"
COMMAND_LIST_RECENT_BADGE="$(command_field_by_id "$COMMAND_LIST_RESPONSE" "markCurrentWorkspaceAttentionRead" "ranking.badge")"
if [ -z "${COMMAND_LIST_TITLE:-}" ] ||
   [ -z "${COMMAND_LIST_CATEGORY:-}" ] ||
   [ -z "${COMMAND_LIST_DESCRIPTION:-}" ] ||
   [ -z "${COMMAND_LIST_PROTOCOL_METHOD:-}" ] ||
   [ -z "${COMMAND_LIST_SYSTEM_IMAGE:-}" ] ||
   [ "$COMMAND_LIST_NEW_WORKSPACE_METHOD" != "command.run" ] ||
   [ "$COMMAND_LIST_WEB_BACK_CATALOG_ID" != "web-back" ] ||
   [ "$COMMAND_LIST_WEB_FORWARD_CATALOG_ID" != "web-forward" ] ||
   [ "$COMMAND_LIST_WEB_BACK_METHOD" != "command.run" ] ||
   [ "$COMMAND_LIST_WEB_FORWARD_METHOD" != "command.run" ] ||
   [ "$COMMAND_LIST_FILE_OPEN_CATALOG_ID" != "file-open-external" ] ||
   [ "$COMMAND_LIST_FILE_REVEAL_CATALOG_ID" != "file-reveal-finder" ] ||
   [ "$COMMAND_LIST_FILE_OPEN_METHOD" != "command.run" ] ||
   [ "$COMMAND_LIST_FILE_REVEAL_METHOD" != "command.run" ] ||
   [ "$COMMAND_LIST_DUPLICATE_WORKSPACE_CATALOG_ID" != "duplicate-workspace" ] ||
   [ "$COMMAND_LIST_CLOSE_OTHER_WORKSPACES_CATALOG_ID" != "close-other-workspaces" ] ||
   [ "$COMMAND_LIST_CLOSE_WORKSPACES_RIGHT_CATALOG_ID" != "close-workspaces-to-right" ] ||
   [ "$COMMAND_LIST_CLOSE_CURRENT_WORKSPACE_CATALOG_ID" != "close-current-workspace" ] ||
   [ "$COMMAND_LIST_WORKSPACE_ROOT_CATALOG_ID" != "workspace-open-root" ] ||
   [ "$COMMAND_LIST_WORKSPACE_SERVICE_CATALOG_ID" != "workspace-open-service" ] ||
   [ "$COMMAND_LIST_RENAME_WORKSPACE_CATALOG_ID" != "rename-workspace" ] ||
   [ "$COMMAND_LIST_DUPLICATE_WORKSPACE_METHOD" != "command.run" ] ||
   [ "$COMMAND_LIST_CLOSE_OTHER_WORKSPACES_METHOD" != "command.run" ] ||
   [ "$COMMAND_LIST_CLOSE_WORKSPACES_RIGHT_METHOD" != "command.run" ] ||
   [ "$COMMAND_LIST_CLOSE_CURRENT_WORKSPACE_METHOD" != "command.run" ] ||
   [ "$COMMAND_LIST_WORKSPACE_ROOT_METHOD" != "command.run" ] ||
   [ "$COMMAND_LIST_WORKSPACE_SERVICE_METHOD" != "command.run" ] ||
   [ "$COMMAND_LIST_RENAME_WORKSPACE_METHOD" != "command.run" ] ||
   [ "$COMMAND_LIST_RECENT_RANK" != "0" ] ||
   [ "$COMMAND_LIST_RECENT_FLAG" != "true" ] ||
   [ -z "${COMMAND_LIST_RECENT_BADGE:-}" ]; then
  echo "control-smoke.sh: command list did not expose canonical command metadata" >&2
  echo "$COMMAND_LIST_RESPONSE" >&2
  exit 1
fi
run command run toggleSettings
sleep 0.2
DIAGNOSTICS_AFTER_SETTINGS_SAMPLE="$(capture diagnostics)"
if ! recent_performance_budget_seen "$DIAGNOSTICS_AFTER_SETTINGS_SAMPLE" "settings.open"; then
  echo "control-smoke.sh: diagnostics did not expose a sampled settings-open budget" >&2
  exit 1
fi
run command run toggleSettings
run command run toggleCommandPalette
sleep 0.2
DIAGNOSTICS_AFTER_PALETTE_SAMPLE="$(capture diagnostics)"
if ! recent_performance_budget_seen "$DIAGNOSTICS_AFTER_PALETTE_SAMPLE" "command-palette.open"; then
  echo "control-smoke.sh: diagnostics did not expose a sampled command-palette budget" >&2
  exit 1
fi
PERFORMANCE_REPORT_SAMPLED_COUNT="$(printf '%s' "$DIAGNOSTICS_AFTER_PALETTE_SAMPLE" | extract_raw result.performance.report.sampledBudgetCount)"
PERFORMANCE_REPORT_RECENT_COUNT="$(printf '%s' "$DIAGNOSTICS_AFTER_PALETTE_SAMPLE" | extract_raw result.performance.report.recentSampleCount)"
if [ "${PERFORMANCE_REPORT_SAMPLED_COUNT:-0}" -lt 5 ] || [ "${PERFORMANCE_REPORT_RECENT_COUNT:-0}" -lt 5 ]; then
  echo "control-smoke.sh: performance report did not summarize sampled budgets" >&2
  exit 1
fi
run command run toggleCommandPalette
echo "control-smoke.sh: notify Control smoke --body Control protocol smoke test completed."
NOTIFY_RESPONSE="$("$CLI" notify "Control smoke" --body "Control protocol smoke test completed.")"
NOTIFICATION_ID="$(printf '%s' "$NOTIFY_RESPONSE" | plutil -extract result.notificationID raw -o - -)"
if [ -z "$NOTIFICATION_ID" ]; then
  echo "control-smoke.sh: notification.create did not return a notificationID" >&2
  exit 1
fi
run notify list
run notify focus "$NOTIFICATION_ID"
run notify clear "$NOTIFICATION_ID"
run notify clear

echo "control-smoke.sh: ok"
