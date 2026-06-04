#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

if [[ -x /usr/local/opt/swift/bin/swift ]]; then
  export PATH="/usr/local/opt/swift/bin:$PATH"
fi

DOGFOOD_TMP="${CONDUCTOR_DOGFOOD_TMPDIR:-$(mktemp -d /tmp/conductor-dogfood.XXXXXX)}"
KEEP_TMP="${CONDUCTOR_DOGFOOD_KEEP_TMP:-0}"
APP_PID=""

cleanup() {
  stop_app
  if [[ "$KEEP_TMP" != "1" && -n "${DOGFOOD_TMP:-}" && -d "$DOGFOOD_TMP" ]]; then
    rm -rf "$DOGFOOD_TMP"
  fi
}
trap cleanup EXIT

section() {
  printf '\n== %s ==\n' "$*"
}

fail() {
  echo "dogfood-workbench.sh: $*" >&2
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
  echo "dogfood-workbench.sh: $*" >&2
  CONDUCTOR_CONTROL_SOCKET_PATH="$SOCKET_PATH" "$CLI_BIN" "$@"
}

run() {
  capture "$@" >/dev/null
}

send_terminal_command() {
  local text="$1"
  run terminal send --text "$text"
  run terminal send-key enter
}

send_terminal_command_to() {
  local terminal_id="$1"
  local text="$2"
  run terminal send --target "$terminal_id" --text "$text"
  run terminal send-key enter --target "$terminal_id"
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

start_app() {
  rm -f "$SOCKET_PATH"
  CONDUCTOR_STATE_PATH="$STATE_PATH" \
  CONDUCTOR_CONTROL_SOCKET_PATH="$SOCKET_PATH" \
  "$APP_BIN" >"$APP_LOG" 2>&1 &
  APP_PID="$!"
  wait_for_socket
}

stop_app() {
  if [[ -n "${APP_PID:-}" ]] && kill -0 "$APP_PID" 2>/dev/null; then
    if [[ -S "${SOCKET_PATH:-}" ]]; then
      CONDUCTOR_CONTROL_SOCKET_PATH="$SOCKET_PATH" "$CLI_BIN" quit >/dev/null 2>&1 || true
      for _ in {1..40}; do
        if ! kill -0 "$APP_PID" 2>/dev/null; then
          APP_PID=""
          return
        fi
        sleep 0.25
      done
    fi
    kill "$APP_PID" 2>/dev/null || true
    wait "$APP_PID" 2>/dev/null || true
  fi
  APP_PID=""
}

require_int_at_least() {
  local value="$1"
  local minimum="$2"
  local label="$3"
  if [[ -z "$value" || "$value" -lt "$minimum" ]]; then
    fail "expected $label >= $minimum, got ${value:-<missing>}"
  fi
}

require_equal() {
  local actual="$1"
  local expected="$2"
  local label="$3"
  if [[ "$actual" != "$expected" ]]; then
    fail "expected $label to be $expected, got ${actual:-<missing>}"
  fi
}

wait_for_state_contains() {
  local needle="$1"
  local label="$2"
  for _ in {1..40}; do
    if [[ -s "$STATE_PATH" ]] && grep -Fq "$needle" "$STATE_PATH"; then
      return 0
    fi
    sleep 0.25
  done
  fail "session state did not persist $label"
}

state_selected_workspace_id() {
  awk '
    /^selectedWorkspaceID:/ {
      if ($2 != "") {
        print $2
        exit
      }
      selected = 1
      next
    }
    selected && $1 == "rawValue:" {
      print $2
      exit
    }
    selected && NF {
      selected = 0
    }
  ' "$STATE_PATH"
}

wait_for_state_selected_workspace() {
  local expected="$1"
  local label="$2"
  local selected
  for _ in {1..40}; do
    if [[ -s "$STATE_PATH" ]]; then
      selected="$(state_selected_workspace_id)"
      if [[ "$selected" == "$expected" ]]; then
        return 0
      fi
    fi
    sleep 0.25
  done
  fail "session state did not persist $label"
}

wait_for_browser_text() {
  local web_tab_id="$1"
  local text="$2"
  for _ in {1..40}; do
    echo "dogfood-workbench.sh: browser wait text $text --web-tab $web_tab_id" >&2
    if CONDUCTOR_CONTROL_SOCKET_PATH="$SOCKET_PATH" "$CLI_BIN" \
      browser wait text "$text" --web-tab "$web_tab_id" --timeout 0.5 >/dev/null 2>/dev/null; then
      return 0
    fi
    sleep 0.25
  done
  fail "browser tab $web_tab_id did not show text: $text"
}

browser_evaluate_result() {
  local web_tab_id="$1"
  local script="$2"
  local response
  response="$(capture browser evaluate "$script" --web-tab "$web_tab_id")"
  printf '%s' "$response" | extract_raw result.result
}

wait_for_browser_scroll_at_least() {
  local web_tab_id="$1"
  local minimum="$2"
  local value
  for _ in {1..40}; do
    echo "dogfood-workbench.sh: browser evaluate scrollY --web-tab $web_tab_id" >&2
    value="$(browser_evaluate_result "$web_tab_id" "Math.round(window.pageYOffset || document.documentElement.scrollTop || document.body.scrollTop || 0)")"
    if [[ -n "$value" && "$value" -ge "$minimum" ]]; then
      return 0
    fi
    sleep 0.25
  done
  fail "browser tab $web_tab_id did not restore scrollY >= $minimum, got ${value:-<missing>}"
}

wait_for_terminal_text() {
  local terminal_id="$1"
  local text="$2"
  local response
  local visible
  for _ in {1..40}; do
    echo "dogfood-workbench.sh: terminal visible-text --target $terminal_id" >&2
    response="$(capture terminal visible-text --target "$terminal_id" 2>/dev/null || true)"
    visible="$(printf '%s' "$response" | extract_raw result.text 2>/dev/null || true)"
    if [[ "$visible" == *"$text"* ]]; then
      return 0
    fi
    sleep 0.25
  done
  fail "terminal $terminal_id did not show text: $text"
}

wait_for_terminal_agent_resume() {
  local terminal_id="$1"
  local expected_command="$2"
  local response
  local resume_command
  for _ in {1..40}; do
    echo "dogfood-workbench.sh: terminal agent --target $terminal_id" >&2
    response="$(capture terminal agent --target "$terminal_id" 2>/dev/null || true)"
    resume_command="$(printf '%s' "$response" | extract_raw result.agent.resumeCommand 2>/dev/null || true)"
    if [[ "$resume_command" == "$expected_command" ]]; then
      return 0
    fi
    sleep 0.25
  done
  fail "terminal $terminal_id did not expose agent resume command $expected_command, got ${resume_command:-<missing>}"
}

browser_tab_id_for_url() {
  local expected_url="$1"
  local response
  response="$(capture surface list)"
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
  fail "could not find browser tab for $expected_url"
}

session_inspect_workspace_index() {
  local response="$1"
  local workspace_id="$2"
  local index
  for index in $(seq 0 40); do
    local candidate_id
    candidate_id="$(printf '%s' "$response" | extract_raw "result.surfaces.workspaces.$index.id" 2>/dev/null || true)"
    if [[ "$candidate_id" == "$workspace_id" ]]; then
      printf '%s\n' "$index"
      return 0
    fi
  done
  fail "session inspect did not include workspace $workspace_id"
}

session_inspect_terminal_id_for_title() {
  local response="$1"
  local workspace_id="$2"
  local expected_title="$3"
  session_inspect_terminal_field_for_title "$response" "$workspace_id" "$expected_title" "id"
}

session_inspect_terminal_field_for_title() {
  local response="$1"
  local workspace_id="$2"
  local expected_title="$3"
  local field="$4"
  local workspace_index
  workspace_index="$(session_inspect_workspace_index "$response" "$workspace_id")"
  local index
  for index in $(seq 0 40); do
    local title
    title="$(printf '%s' "$response" | extract_raw "result.surfaces.workspaces.$workspace_index.terminals.$index.title" 2>/dev/null || true)"
    if [[ "$title" == "$expected_title" ]]; then
      printf '%s\n' "$(printf '%s' "$response" | extract_raw "result.surfaces.workspaces.$workspace_index.terminals.$index.$field" 2>/dev/null || true)"
      return 0
    fi
  done
  fail "session inspect did not include terminal titled $expected_title"
}

session_inspect_has_terminal_issue() {
  local response="$1"
  local terminal_id="$2"
  local expected_kind="$3"
  local index
  for index in $(seq 0 80); do
    local kind
    local candidate_terminal_id
    kind="$(printf '%s' "$response" | extract_raw "result.surfaces.issues.$index.kind" 2>/dev/null || true)"
    candidate_terminal_id="$(printf '%s' "$response" | extract_raw "result.surfaces.issues.$index.terminalID" 2>/dev/null || true)"
    if [[ "$kind" == "$expected_kind" && "$candidate_terminal_id" == "$terminal_id" ]]; then
      return 0
    fi
  done
  return 1
}

session_inspect_web_tab_id_for_url() {
  local response="$1"
  local workspace_id="$2"
  local expected_url="$3"
  local workspace_index
  workspace_index="$(session_inspect_workspace_index "$response" "$workspace_id")"
  local index
  for index in $(seq 0 40); do
    local url
    local web_tab_id
    url="$(printf '%s' "$response" | extract_raw "result.surfaces.workspaces.$workspace_index.webTabs.$index.url" 2>/dev/null || true)"
    web_tab_id="$(printf '%s' "$response" | extract_raw "result.surfaces.workspaces.$workspace_index.webTabs.$index.id" 2>/dev/null || true)"
    if [[ "$url" == "$expected_url" && -n "$web_tab_id" ]]; then
      printf '%s\n' "$web_tab_id"
      return 0
    fi
  done
  fail "session inspect did not include browser tab for $expected_url"
}

session_inspect_file_tab_id_for_path() {
  local response="$1"
  local workspace_id="$2"
  local expected_path="$3"
  local workspace_index
  workspace_index="$(session_inspect_workspace_index "$response" "$workspace_id")"
  local index
  for index in $(seq 0 40); do
    local path
    local file_tab_id
    path="$(printf '%s' "$response" | extract_raw "result.surfaces.workspaces.$workspace_index.files.$index.path" 2>/dev/null || true)"
    file_tab_id="$(printf '%s' "$response" | extract_raw "result.surfaces.workspaces.$workspace_index.files.$index.id" 2>/dev/null || true)"
    if [[ "$path" == "$expected_path" && -n "$file_tab_id" ]]; then
      printf '%s\n' "$file_tab_id"
      return 0
    fi
  done
  fail "session inspect did not include file tab for $expected_path"
}

mkdir -p "$DOGFOOD_TMP"
STATE_PATH="$DOGFOOD_TMP/window-state.yaml"
PREVIOUS_STATE_PATH="$DOGFOOD_TMP/window-state.previous.yaml"
SOCKET_PATH="$DOGFOOD_TMP/control.sock"
APP_LOG="$DOGFOOD_TMP/conductor.log"
DIAGNOSTICS_DIR="$DOGFOOD_TMP/diagnostics"
FIXTURE_PATH="$ROOT/Scripts/fixtures/browser-automation.html"
FIXTURE_URL="file://${FIXTURE_PATH// /%20}"
HISTORY_URL_1="$FIXTURE_URL?history=release-1"
HISTORY_URL_2="$FIXTURE_URL?history=release-2"
NORMAL_RESTORE_FILE_PATH="$DOGFOOD_TMP/normal-restore-file.txt"
RESTORE_FILE_PATH="$DOGFOOD_TMP/restore-file.txt"
FAKE_BIN_DIR="$DOGFOOD_TMP/fake-bin"

mkdir -p "$FAKE_BIN_DIR"
cat >"$FAKE_BIN_DIR/codex" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

printf 'dogfood fake codex invoked: %s\n' "$*"
if [[ "${1:-}" == "resume" && -n "${2:-}" ]]; then
  printf 'dogfood fake codex resumed session %s\n' "$2"
  exit 0
fi

printf 'dogfood fake codex unsupported command\n' >&2
exit 2
EOF
chmod +x "$FAKE_BIN_DIR/codex"
export PATH="$FAKE_BIN_DIR:$PATH"

if [[ "${CONDUCTOR_DOGFOOD_SKIP_BUILD:-0}" != "1" ]]; then
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
start_app
run ping

create_workspace() {
  local title="$1"
  local response
  response="$(capture workspace create --title "$title")"
  printf '%s' "$response" | extract_raw result.workspaceID
}

setup_workspace() {
  local workspace_id="$1"
  local title="$2"
  local marker="$3"

  section "workspace: $title"
  run workspace select "$workspace_id"
  run surface split --direction right
  send_terminal_command "printf '$marker terminal left ready\\n'"
  run surface focus
  send_terminal_command "printf '$marker terminal right ready\\n'"
  run browser open "$FIXTURE_URL"
  capture browser wait load --timeout 10 >/dev/null
  capture browser snapshot >"$DOGFOOD_TMP/$marker-browser-snapshot.json"
  capture browser screenshot >"$DOGFOOD_TMP/$marker-browser-screenshot.json"
  capture notify "$title needs review" --body "$marker completed through the control protocol." >"$DOGFOOD_TMP/$marker-notification.json"
}

APP_WORKSPACE_ID="$(create_workspace "Dogfood App")"
BACKEND_WORKSPACE_ID="$(create_workspace "Dogfood Backend")"
RELEASE_WORKSPACE_ID="$(create_workspace "Dogfood Release")"

setup_workspace "$APP_WORKSPACE_ID" "Dogfood App" app
setup_workspace "$BACKEND_WORKSPACE_ID" "Dogfood Backend" backend
setup_workspace "$RELEASE_WORKSPACE_ID" "Dogfood Release" release
RELEASE_TERMINAL_STATUS_RESPONSE="$(capture status)"
RELEASE_TERMINAL_ID="$(printf '%s' "$RELEASE_TERMINAL_STATUS_RESPONSE" | extract_raw result.focusedTerminalID)"
RELEASE_TERMINAL_TITLE="Dogfood Release Terminal"
RELEASE_TERMINAL_MARKER="release terminal right ready"
RELEASE_AGENT_SESSION_ID="019e029c-b1e9-7e31-992e-df4638cf8ee8"
RELEASE_AGENT_RESUME_COMMAND="codex resume $RELEASE_AGENT_SESSION_ID"
capture terminal rename "$RELEASE_TERMINAL_TITLE" --target "$RELEASE_TERMINAL_ID" >"$DOGFOOD_TMP/release-terminal-rename.json"
RELEASE_TERMINAL_CWD_RESPONSE="$(capture terminal cwd --target "$RELEASE_TERMINAL_ID")"
RELEASE_TERMINAL_CWD="$(printf '%s' "$RELEASE_TERMINAL_CWD_RESPONSE" | extract_raw result.cwd)"
wait_for_terminal_text "$RELEASE_TERMINAL_ID" "$RELEASE_TERMINAL_MARKER"
send_terminal_command "echo 'To continue this session, run $RELEASE_AGENT_RESUME_COMMAND'"
wait_for_terminal_text "$RELEASE_TERMINAL_ID" "$RELEASE_AGENT_RESUME_COMMAND"
wait_for_terminal_agent_resume "$RELEASE_TERMINAL_ID" "$RELEASE_AGENT_RESUME_COMMAND"

section "dogfood assertions"
STATUS_RESPONSE="$(capture status)"
WORKSPACE_COUNT="$(printf '%s' "$STATUS_RESPONSE" | extract_raw result.workspaceCount)"
WEB_TAB_COUNT="$(printf '%s' "$STATUS_RESPONSE" | extract_raw result.webTabCount)"
UNREAD_COUNT="$(printf '%s' "$STATUS_RESPONSE" | extract_raw result.attentionUnreadCount)"
require_int_at_least "$WORKSPACE_COUNT" 3 "workspaceCount"
require_int_at_least "$WEB_TAB_COUNT" 3 "webTabCount"
require_int_at_least "$UNREAD_COUNT" 3 "attentionUnreadCount"

section "session restore normal"
printf 'dogfood normal restore file\n' >"$NORMAL_RESTORE_FILE_PATH"
run workspace select "$RELEASE_WORKSPACE_ID"
RELEASE_HISTORY_WEB_TAB_ID="$(browser_tab_id_for_url "$FIXTURE_URL")"
run browser select "$RELEASE_HISTORY_WEB_TAB_ID" --workspace "$RELEASE_WORKSPACE_ID"
capture browser navigate "$HISTORY_URL_1" --web-tab "$RELEASE_HISTORY_WEB_TAB_ID" >/dev/null
wait_for_browser_text "$RELEASE_HISTORY_WEB_TAB_ID" "History marker: release-1"
capture browser navigate "$HISTORY_URL_2" --web-tab "$RELEASE_HISTORY_WEB_TAB_ID" >/dev/null
wait_for_browser_text "$RELEASE_HISTORY_WEB_TAB_ID" "History marker: release-2"
RESTORE_SCROLL_Y="$(browser_evaluate_result "$RELEASE_HISTORY_WEB_TAB_ID" "window.scrollTo(0, document.body.scrollHeight); Math.round(window.pageYOffset || document.documentElement.scrollTop || document.body.scrollTop || 0)")"
require_int_at_least "$RESTORE_SCROLL_Y" 400 "browser scroll capture"
run file open "$NORMAL_RESTORE_FILE_PATH"
capture file snapshot --target "$NORMAL_RESTORE_FILE_PATH" --text >"$DOGFOOD_TMP/normal-restore-file-snapshot.json"
capture notify "Normal restore marker" --body "This unread event should survive a normal relaunch." >"$DOGFOOD_TMP/normal-restore-notification.json"
wait_for_state_contains "$RELEASE_WORKSPACE_ID" "selected release workspace"
wait_for_state_contains "$HISTORY_URL_2" "normal restore browser history URL"
wait_for_state_contains "scrollY" "normal restore browser scroll position"
wait_for_state_contains "$RELEASE_TERMINAL_TITLE" "normal restore terminal title"
wait_for_state_contains "$NORMAL_RESTORE_FILE_PATH" "normal restore file tab"
stop_app
start_app
run ping
NORMAL_RESTORE_STATUS_RESPONSE="$(capture status)"
NORMAL_RESTORE_STATE="$(printf '%s' "$NORMAL_RESTORE_STATUS_RESPONSE" | extract_raw result.sessionRestore.state)"
NORMAL_RESTORE_SELECTED_WORKSPACE_ID="$(printf '%s' "$NORMAL_RESTORE_STATUS_RESPONSE" | extract_raw result.selectedWorkspaceID)"
NORMAL_RESTORE_WORKSPACE_COUNT="$(printf '%s' "$NORMAL_RESTORE_STATUS_RESPONSE" | extract_raw result.workspaceCount)"
NORMAL_RESTORE_WEB_TAB_COUNT="$(printf '%s' "$NORMAL_RESTORE_STATUS_RESPONSE" | extract_raw result.webTabCount)"
NORMAL_RESTORE_FILE_TAB_COUNT="$(printf '%s' "$NORMAL_RESTORE_STATUS_RESPONSE" | extract_raw result.fileTabCount)"
NORMAL_RESTORE_UNREAD_COUNT="$(printf '%s' "$NORMAL_RESTORE_STATUS_RESPONSE" | extract_raw result.attentionUnreadCount)"
require_equal "$NORMAL_RESTORE_STATE" "restored" "normal session restore state"
require_equal "$NORMAL_RESTORE_SELECTED_WORKSPACE_ID" "$RELEASE_WORKSPACE_ID" "normal restored selected workspace"
require_int_at_least "$NORMAL_RESTORE_WORKSPACE_COUNT" 3 "normal restored workspaceCount"
require_int_at_least "$NORMAL_RESTORE_WEB_TAB_COUNT" 3 "normal restored webTabCount"
require_int_at_least "$NORMAL_RESTORE_FILE_TAB_COUNT" 1 "normal restored fileTabCount"
require_int_at_least "$NORMAL_RESTORE_UNREAD_COUNT" 4 "normal restored attentionUnreadCount"
NORMAL_RESTORE_TERMINAL_TITLE_RESPONSE="$(capture terminal title --target "$RELEASE_TERMINAL_ID")"
NORMAL_RESTORE_TERMINAL_TITLE="$(printf '%s' "$NORMAL_RESTORE_TERMINAL_TITLE_RESPONSE" | extract_raw result.userTitle)"
NORMAL_RESTORE_TERMINAL_CWD_RESPONSE="$(capture terminal cwd --target "$RELEASE_TERMINAL_ID")"
NORMAL_RESTORE_TERMINAL_CWD="$(printf '%s' "$NORMAL_RESTORE_TERMINAL_CWD_RESPONSE" | extract_raw result.cwd)"
NORMAL_RESTORE_AGENT_RESPONSE="$(capture terminal agent --target "$RELEASE_TERMINAL_ID")"
NORMAL_RESTORE_AGENT_RESUME_COMMAND="$(printf '%s' "$NORMAL_RESTORE_AGENT_RESPONSE" | extract_raw result.agent.resumeCommand)"
NORMAL_RESTORE_AGENT_SESSION_ID="$(printf '%s' "$NORMAL_RESTORE_AGENT_RESPONSE" | extract_raw result.agent.sessionIdentifier)"
require_equal "$NORMAL_RESTORE_TERMINAL_TITLE" "$RELEASE_TERMINAL_TITLE" "normal restored terminal userTitle"
require_equal "$NORMAL_RESTORE_TERMINAL_CWD" "$RELEASE_TERMINAL_CWD" "normal restored terminal cwd"
require_equal "$NORMAL_RESTORE_AGENT_RESUME_COMMAND" "$RELEASE_AGENT_RESUME_COMMAND" "normal restored agent resume command"
require_equal "$NORMAL_RESTORE_AGENT_SESSION_ID" "$RELEASE_AGENT_SESSION_ID" "normal restored agent session id"
NORMAL_RESTORE_AGENT_RESUME_DRY_RUN_RESPONSE="$(capture terminal resume-agent --target "$RELEASE_TERMINAL_ID" --dry-run)"
NORMAL_RESTORE_AGENT_RESUME_DRY_RUN_COMMAND="$(printf '%s' "$NORMAL_RESTORE_AGENT_RESUME_DRY_RUN_RESPONSE" | extract_raw result.resumeCommand)"
NORMAL_RESTORE_AGENT_RESUME_DRY_RUN_SENT="$(printf '%s' "$NORMAL_RESTORE_AGENT_RESUME_DRY_RUN_RESPONSE" | extract_raw result.sent)"
NORMAL_RESTORE_AGENT_RESUME_DRY_RUN_FLAG="$(printf '%s' "$NORMAL_RESTORE_AGENT_RESUME_DRY_RUN_RESPONSE" | extract_raw result.dryRun)"
require_equal "$NORMAL_RESTORE_AGENT_RESUME_DRY_RUN_COMMAND" "$RELEASE_AGENT_RESUME_COMMAND" "normal restored agent resume dry-run command"
require_equal "$NORMAL_RESTORE_AGENT_RESUME_DRY_RUN_SENT" "false" "normal restored agent resume dry-run sent"
require_equal "$NORMAL_RESTORE_AGENT_RESUME_DRY_RUN_FLAG" "true" "normal restored agent resume dry-run flag"
NORMAL_RESTORE_AGENT_BATCH_DRY_RUN_RESPONSE="$(capture terminal resume-agents --workspace current --dry-run)"
NORMAL_RESTORE_AGENT_BATCH_TARGET_COUNT="$(printf '%s' "$NORMAL_RESTORE_AGENT_BATCH_DRY_RUN_RESPONSE" | extract_raw result.targetCount)"
NORMAL_RESTORE_AGENT_BATCH_SENT_COUNT="$(printf '%s' "$NORMAL_RESTORE_AGENT_BATCH_DRY_RUN_RESPONSE" | extract_raw result.sentCount)"
NORMAL_RESTORE_AGENT_BATCH_COMMAND="$(printf '%s' "$NORMAL_RESTORE_AGENT_BATCH_DRY_RUN_RESPONSE" | extract_raw result.results.0.resumeCommand)"
NORMAL_RESTORE_AGENT_BATCH_TERMINAL_ID="$(printf '%s' "$NORMAL_RESTORE_AGENT_BATCH_DRY_RUN_RESPONSE" | extract_raw result.results.0.terminalID)"
require_int_at_least "$NORMAL_RESTORE_AGENT_BATCH_TARGET_COUNT" 1 "normal restored agent batch targetCount"
require_equal "$NORMAL_RESTORE_AGENT_BATCH_SENT_COUNT" "0" "normal restored agent batch dry-run sentCount"
require_equal "$NORMAL_RESTORE_AGENT_BATCH_COMMAND" "$RELEASE_AGENT_RESUME_COMMAND" "normal restored agent batch resume command"
require_equal "$NORMAL_RESTORE_AGENT_BATCH_TERMINAL_ID" "$RELEASE_TERMINAL_ID" "normal restored agent batch terminal id"
send_terminal_command_to "$RELEASE_TERMINAL_ID" "export PATH=$FAKE_BIN_DIR:\$PATH"
send_terminal_command_to "$RELEASE_TERMINAL_ID" "printf 'dogfood fake agent path ready\\n'"
wait_for_terminal_text "$RELEASE_TERMINAL_ID" "dogfood fake agent path ready"
NORMAL_RESTORE_AGENT_BATCH_RUN_RESPONSE="$(capture terminal resume-agents --workspace current)"
NORMAL_RESTORE_AGENT_BATCH_RUN_SENT_COUNT="$(printf '%s' "$NORMAL_RESTORE_AGENT_BATCH_RUN_RESPONSE" | extract_raw result.sentCount)"
NORMAL_RESTORE_AGENT_BATCH_RUN_SENT="$(printf '%s' "$NORMAL_RESTORE_AGENT_BATCH_RUN_RESPONSE" | extract_raw result.results.0.sent)"
NORMAL_RESTORE_AGENT_BATCH_RUN_DRY_RUN="$(printf '%s' "$NORMAL_RESTORE_AGENT_BATCH_RUN_RESPONSE" | extract_raw result.dryRun)"
require_int_at_least "$NORMAL_RESTORE_AGENT_BATCH_RUN_SENT_COUNT" 1 "normal restored agent batch sentCount"
require_equal "$NORMAL_RESTORE_AGENT_BATCH_RUN_SENT" "true" "normal restored agent batch sent flag"
require_equal "$NORMAL_RESTORE_AGENT_BATCH_RUN_DRY_RUN" "false" "normal restored agent batch run dryRun flag"
wait_for_terminal_text "$RELEASE_TERMINAL_ID" "dogfood fake codex resumed session $RELEASE_AGENT_SESSION_ID"
wait_for_terminal_text "$RELEASE_TERMINAL_ID" "$RELEASE_TERMINAL_MARKER"
NORMAL_RESTORE_SURFACES_RESPONSE="$(capture surface list)"
NORMAL_RESTORE_FILE_FOUND="0"
NORMAL_RESTORE_BROWSER_FOUND="0"
for index in $(seq 0 20); do
  NORMAL_RESTORE_SURFACE_TYPE="$(printf '%s' "$NORMAL_RESTORE_SURFACES_RESPONSE" | extract_raw "result.surfaces.$index.type" 2>/dev/null || true)"
  NORMAL_RESTORE_SURFACE_PATH="$(printf '%s' "$NORMAL_RESTORE_SURFACES_RESPONSE" | extract_raw "result.surfaces.$index.path" 2>/dev/null || true)"
  NORMAL_RESTORE_SURFACE_URL="$(printf '%s' "$NORMAL_RESTORE_SURFACES_RESPONSE" | extract_raw "result.surfaces.$index.url" 2>/dev/null || true)"
  if [[ "$NORMAL_RESTORE_SURFACE_TYPE" == "file" && "$NORMAL_RESTORE_SURFACE_PATH" == "$NORMAL_RESTORE_FILE_PATH" ]]; then
    NORMAL_RESTORE_FILE_FOUND="1"
  fi
  if [[ "$NORMAL_RESTORE_SURFACE_TYPE" == "browser" && "$NORMAL_RESTORE_SURFACE_URL" == "$HISTORY_URL_2" ]]; then
    NORMAL_RESTORE_BROWSER_FOUND="1"
  fi
done
if [[ "$NORMAL_RESTORE_FILE_FOUND" != "1" ]]; then
  fail "normal session restore did not restore the expected file tab"
fi
if [[ "$NORMAL_RESTORE_BROWSER_FOUND" != "1" ]]; then
  fail "normal session restore did not restore the expected browser URL"
fi
NORMAL_RESTORE_INSPECT_RESPONSE="$(capture session inspect)"
NORMAL_RESTORE_INSPECT_TERMINAL_COUNT="$(printf '%s' "$NORMAL_RESTORE_INSPECT_RESPONSE" | extract_raw result.surfaces.terminalCount)"
NORMAL_RESTORE_INSPECT_BROWSER_COUNT="$(printf '%s' "$NORMAL_RESTORE_INSPECT_RESPONSE" | extract_raw result.surfaces.browserCount)"
NORMAL_RESTORE_INSPECT_FILE_COUNT="$(printf '%s' "$NORMAL_RESTORE_INSPECT_RESPONSE" | extract_raw result.surfaces.fileCount)"
NORMAL_RESTORE_INSPECT_ISSUE_COUNT="$(printf '%s' "$NORMAL_RESTORE_INSPECT_RESPONSE" | extract_raw result.surfaces.issueCount)"
NORMAL_RESTORE_INSPECT_CRITICAL_COUNT="$(printf '%s' "$NORMAL_RESTORE_INSPECT_RESPONSE" | extract_raw result.surfaces.criticalIssueCount)"
NORMAL_RESTORE_INSPECT_WARNING_COUNT="$(printf '%s' "$NORMAL_RESTORE_INSPECT_RESPONSE" | extract_raw result.surfaces.warningIssueCount)"
require_int_at_least "$NORMAL_RESTORE_INSPECT_TERMINAL_COUNT" 3 "normal session inspect terminalCount"
require_int_at_least "$NORMAL_RESTORE_INSPECT_BROWSER_COUNT" 3 "normal session inspect browserCount"
require_int_at_least "$NORMAL_RESTORE_INSPECT_FILE_COUNT" 1 "normal session inspect fileCount"
require_int_at_least "$NORMAL_RESTORE_INSPECT_ISSUE_COUNT" 0 "normal session inspect issueCount"
require_int_at_least "$NORMAL_RESTORE_INSPECT_CRITICAL_COUNT" 0 "normal session inspect criticalIssueCount"
require_int_at_least "$NORMAL_RESTORE_INSPECT_WARNING_COUNT" 0 "normal session inspect warningIssueCount"
NORMAL_RESTORE_INSPECT_TERMINAL_ID="$(session_inspect_terminal_id_for_title "$NORMAL_RESTORE_INSPECT_RESPONSE" "$RELEASE_WORKSPACE_ID" "$RELEASE_TERMINAL_TITLE")"
NORMAL_RESTORE_INSPECT_TERMINAL_PROCESS_STATUS="$(session_inspect_terminal_field_for_title "$NORMAL_RESTORE_INSPECT_RESPONSE" "$RELEASE_WORKSPACE_ID" "$RELEASE_TERMINAL_TITLE" "process.status")"
NORMAL_RESTORE_INSPECT_TERMINAL_PROCESS_REATTACHED="$(session_inspect_terminal_field_for_title "$NORMAL_RESTORE_INSPECT_RESPONSE" "$RELEASE_WORKSPACE_ID" "$RELEASE_TERMINAL_TITLE" "process.reattached")"
require_equal "$NORMAL_RESTORE_INSPECT_TERMINAL_PROCESS_STATUS" "fresh-after-restore" "normal restored terminal process status"
require_equal "$NORMAL_RESTORE_INSPECT_TERMINAL_PROCESS_REATTACHED" "false" "normal restored terminal process reattach flag"
if ! session_inspect_has_terminal_issue "$NORMAL_RESTORE_INSPECT_RESPONSE" "$NORMAL_RESTORE_INSPECT_TERMINAL_ID" "terminal_process_restarted"; then
  fail "normal session inspect did not explain that the restored terminal process was restarted"
fi
NORMAL_RESTORE_INSPECT_WEB_TAB_ID="$(session_inspect_web_tab_id_for_url "$NORMAL_RESTORE_INSPECT_RESPONSE" "$RELEASE_WORKSPACE_ID" "$HISTORY_URL_2")"
NORMAL_RESTORE_INSPECT_FILE_TAB_ID="$(session_inspect_file_tab_id_for_path "$NORMAL_RESTORE_INSPECT_RESPONSE" "$RELEASE_WORKSPACE_ID" "$NORMAL_RESTORE_FILE_PATH")"
NORMAL_RESTORE_TERMINAL_FOCUS_RESPONSE="$(capture surface focus --target "$NORMAL_RESTORE_INSPECT_TERMINAL_ID")"
require_equal "$(printf '%s' "$NORMAL_RESTORE_TERMINAL_FOCUS_RESPONSE" | extract_raw result.type)" "terminal" "normal session inspect terminal focus type"
require_equal "$(printf '%s' "$NORMAL_RESTORE_TERMINAL_FOCUS_RESPONSE" | extract_raw result.terminalID)" "$NORMAL_RESTORE_INSPECT_TERMINAL_ID" "normal session inspect terminal focus target"
require_equal "$(printf '%s' "$NORMAL_RESTORE_TERMINAL_FOCUS_RESPONSE" | extract_raw result.workspaceID)" "$RELEASE_WORKSPACE_ID" "normal session inspect terminal focus workspace"
NORMAL_RESTORE_BROWSER_FOCUS_RESPONSE="$(capture surface focus --web-tab "$NORMAL_RESTORE_INSPECT_WEB_TAB_ID" --workspace "$RELEASE_WORKSPACE_ID")"
require_equal "$(printf '%s' "$NORMAL_RESTORE_BROWSER_FOCUS_RESPONSE" | extract_raw result.type)" "browser" "normal session inspect browser focus type"
require_equal "$(printf '%s' "$NORMAL_RESTORE_BROWSER_FOCUS_RESPONSE" | extract_raw result.webTabID)" "$NORMAL_RESTORE_INSPECT_WEB_TAB_ID" "normal session inspect browser focus target"
require_equal "$(printf '%s' "$NORMAL_RESTORE_BROWSER_FOCUS_RESPONSE" | extract_raw result.workspaceID)" "$RELEASE_WORKSPACE_ID" "normal session inspect browser focus workspace"
NORMAL_RESTORE_FILE_FOCUS_RESPONSE="$(capture surface focus --file-tab "$NORMAL_RESTORE_INSPECT_FILE_TAB_ID" --workspace "$RELEASE_WORKSPACE_ID")"
require_equal "$(printf '%s' "$NORMAL_RESTORE_FILE_FOCUS_RESPONSE" | extract_raw result.type)" "file" "normal session inspect file focus type"
require_equal "$(printf '%s' "$NORMAL_RESTORE_FILE_FOCUS_RESPONSE" | extract_raw result.fileTabID)" "$NORMAL_RESTORE_INSPECT_FILE_TAB_ID" "normal session inspect file focus target"
require_equal "$(printf '%s' "$NORMAL_RESTORE_FILE_FOCUS_RESPONSE" | extract_raw result.workspaceID)" "$RELEASE_WORKSPACE_ID" "normal session inspect file focus workspace"
run browser select "$RELEASE_HISTORY_WEB_TAB_ID" --workspace "$RELEASE_WORKSPACE_ID"
wait_for_browser_text "$RELEASE_HISTORY_WEB_TAB_ID" "History marker: release-2"
wait_for_browser_scroll_at_least "$RELEASE_HISTORY_WEB_TAB_ID" 400
run browser back --web-tab "$RELEASE_HISTORY_WEB_TAB_ID"
wait_for_browser_text "$RELEASE_HISTORY_WEB_TAB_ID" "History marker: release-1"
run browser forward --web-tab "$RELEASE_HISTORY_WEB_TAB_ID"
wait_for_browser_text "$RELEASE_HISTORY_WEB_TAB_ID" "History marker: release-2"

section "session restore previous command"
run workspace select "$APP_WORKSPACE_ID"
wait_for_state_selected_workspace "$APP_WORKSPACE_ID" "app workspace before restore-previous"
RESTORE_PREVIOUS_RESPONSE="$(capture session restore-previous)"
RESTORE_PREVIOUS_STATE="$(printf '%s' "$RESTORE_PREVIOUS_RESPONSE" | extract_raw result.sessionRestore.state)"
require_equal "$RESTORE_PREVIOUS_STATE" "restoredFromPrevious" "restore-previous state"
RESTORE_PREVIOUS_STATUS_RESPONSE="$(capture status)"
RESTORE_PREVIOUS_SELECTED_WORKSPACE_ID="$(printf '%s' "$RESTORE_PREVIOUS_STATUS_RESPONSE" | extract_raw result.selectedWorkspaceID)"
require_equal "$RESTORE_PREVIOUS_SELECTED_WORKSPACE_ID" "$RELEASE_WORKSPACE_ID" "restore-previous selected workspace"

section "session restore fallback"
printf 'dogfood restore file\n' >"$RESTORE_FILE_PATH"
for _ in {1..20}; do
  if [[ -s "$STATE_PATH" ]]; then
    break
  fi
  sleep 0.25
done
if [[ ! -s "$STATE_PATH" ]]; then
  fail "session restore fallback fixture did not produce a current state snapshot"
fi
run workspace select "$APP_WORKSPACE_ID"
run workspace select "$RELEASE_WORKSPACE_ID"
for _ in {1..20}; do
  if [[ -s "$STATE_PATH" ]]; then
    break
  fi
  sleep 0.25
done
stop_app
cp "$STATE_PATH" "$PREVIOUS_STATE_PATH"
PREVIOUS_STATE_FIXTURE="$DOGFOOD_TMP/window-state.previous.fixture.yaml"
awk \
  -v workspaceID="$RELEASE_WORKSPACE_ID" \
  -v filePath="$RESTORE_FILE_PATH" \
  -v rootPath="$DOGFOOD_TMP" '
    /^workspaceContentStates:/ {
      print "workspaceContentStates:"
      print "- workspaceID:"
      print "    rawValue: " workspaceID
      print "  workspaceWebTabs: []"
      print "  workspaceFileTabs:"
      print "  - filePath: " filePath
      print "    rootPath: " rootPath
      exit
    }
    { print }
  ' "$PREVIOUS_STATE_PATH" >"$PREVIOUS_STATE_FIXTURE"
mv "$PREVIOUS_STATE_FIXTURE" "$PREVIOUS_STATE_PATH"
cp "$PREVIOUS_STATE_PATH" "$DOGFOOD_TMP/window-state.previous.fixture-debug.yaml"
for _ in {1..20}; do
  if [[ -s "$PREVIOUS_STATE_PATH" ]]; then
    break
  fi
  sleep 0.25
done
if [[ ! -s "$PREVIOUS_STATE_PATH" ]]; then
  fail "session restore fallback fixture did not produce a previous state snapshot"
fi
if ! grep -q "$RESTORE_FILE_PATH" "$PREVIOUS_STATE_PATH"; then
  fail "session restore fallback fixture did not include the missing file tab"
fi
rm -f "$RESTORE_FILE_PATH"
printf 'not: valid: yaml: [' >"$STATE_PATH"
start_app
run ping
RESTORE_STATUS_RESPONSE="$(capture status)"
RESTORE_STATE="$(printf '%s' "$RESTORE_STATUS_RESPONSE" | extract_raw result.sessionRestore.state)"
RESTORE_FAILED_COUNT="$(printf '%s' "$RESTORE_STATUS_RESPONSE" | extract_raw result.sessionRestore.failedPaths.0 2>/dev/null || true)"
RESTORE_DROPPED_FILE_COUNT="$(printf '%s' "$RESTORE_STATUS_RESPONSE" | extract_raw result.sessionRestore.droppedFileTabCount 2>/dev/null || true)"
RESTORE_MISSING_FILE_PATH="$(printf '%s' "$RESTORE_STATUS_RESPONSE" | extract_raw result.sessionRestore.missingFilePaths.0 2>/dev/null || true)"
if [[ "$RESTORE_STATE" != "restoredFromPrevious" || -z "$RESTORE_FAILED_COUNT" ]]; then
  fail "expected restoredFromPrevious session restore state after corrupting current snapshot"
fi
if [[ "${RESTORE_DROPPED_FILE_COUNT:-0}" -lt 1 || "$RESTORE_MISSING_FILE_PATH" != "$RESTORE_FILE_PATH" ]]; then
  fail "session restore fallback did not report the missing file tab"
fi
RESTORE_NOTIFICATIONS_RESPONSE="$(capture notify list)"
RESTORE_EVENT_FOUND="0"
for index in $(seq 0 20); do
  RESTORE_NOTIFICATION_KIND="$(printf '%s' "$RESTORE_NOTIFICATIONS_RESPONSE" | extract_raw "result.notifications.$index.kind" 2>/dev/null || true)"
  RESTORE_NOTIFICATION_SOURCE="$(printf '%s' "$RESTORE_NOTIFICATIONS_RESPONSE" | extract_raw "result.notifications.$index.source" 2>/dev/null || true)"
  RESTORE_NOTIFICATION_STATE="$(printf '%s' "$RESTORE_NOTIFICATIONS_RESPONSE" | extract_raw "result.notifications.$index.details.state" 2>/dev/null || true)"
  if [[ "$RESTORE_NOTIFICATION_KIND" == "sessionRecovery" &&
        "$RESTORE_NOTIFICATION_SOURCE" == "session-restore" &&
        "$RESTORE_NOTIFICATION_STATE" == "restoredFromPrevious" ]]; then
    RESTORE_EVENT_FOUND="1"
    break
  fi
done
if [[ "$RESTORE_EVENT_FOUND" != "1" ]]; then
  fail "session restore fallback did not create the expected in-app recovery event"
fi

if [[ "${CONDUCTOR_DOGFOOD_RUN_CONTROL_SMOKE:-0}" == "1" ]]; then
  section "control smoke"
  CONDUCTOR_STATE_PATH="$STATE_PATH" \
  CONDUCTOR_CONTROL_SOCKET_PATH="$SOCKET_PATH" \
  CONDUCTOR_CLI_PATH="$CLI_BIN" \
  CONDUCTOR_SMOKE_SKIP_CLI_BUILD=1 \
  ./Scripts/control-smoke.sh
fi

section "diagnostics"
DIAGNOSTICS_RESPONSE="$(capture diagnostics export --output "$DIAGNOSTICS_DIR")"
DIAGNOSTICS_PATH="$(printf '%s' "$DIAGNOSTICS_RESPONSE" | extract_raw result.path)"
if [[ ! -s "$DIAGNOSTICS_PATH/manifest.json" || ! -s "$DIAGNOSTICS_PATH/summary.redacted.json" ]]; then
  fail "diagnostics export did not produce a complete bundle at $DIAGNOSTICS_PATH"
fi

if ! grep -q '"performance"' "$DIAGNOSTICS_PATH/summary.redacted.json"; then
  fail "diagnostics summary is missing performance data"
fi

section "done"
echo "dogfood=ok"
echo "workspaces=$WORKSPACE_COUNT"
echo "webTabs=$WEB_TAB_COUNT"
echo "unread=$UNREAD_COUNT"
echo "artifacts=$DOGFOOD_TMP"
