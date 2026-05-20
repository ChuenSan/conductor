#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LABEL="app.conductor.crash-watch"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
WATCH_DIR="${CONDUCTOR_CRASH_WATCH_DIR:-$HOME/Library/Logs/ConductorCrashWatch}"
PIDFILE="$WATCH_DIR/watcher.pid"
STATE_FILE="$WATCH_DIR/state.env"
WATCH_LOG="$WATCH_DIR/watcher.log"
SUMMARY="$WATCH_DIR/latest-summary.md"
EVENTS="$WATCH_DIR/events.log"
INTERVAL="${CONDUCTOR_CRASH_WATCH_INTERVAL:-8}"

mkdir -p "$WATCH_DIR"

usage() {
  cat <<USAGE
Usage: $(basename "$0") <install|uninstall|start|stop|status|snapshot|daemon>

Commands:
  install     Install and start a user LaunchAgent watcher.
  uninstall   Stop and remove the LaunchAgent watcher.
  start       Start a background watcher for this login session.
  stop        Stop the background watcher.
  status      Print watcher status and recent crash evidence location.
  snapshot    Capture a manual diagnostic snapshot now.
  daemon      Run the watcher loop in the foreground.
USAGE
}

now_iso() {
  date -u +"%Y-%m-%dT%H:%M:%SZ"
}

safe_stamp() {
  date -u +"%Y%m%dT%H%M%SZ"
}

conductor_pids() {
  pgrep -x Conductor 2>/dev/null || true
}

latest_reports() {
  local reports="$HOME/Library/Logs/DiagnosticReports"
  [[ -d "$reports" ]] || return 0
  find "$reports" -maxdepth 1 -type f \( -name 'Conductor*.crash' -o -name 'Conductor*.ips' \) \
    -exec stat -f '%m %N' {} + 2>/dev/null | sort -nr | head -5 | cut -d' ' -f2-
}

latest_report_key() {
  local report
  report="$(latest_reports | head -1)"
  [[ -n "$report" ]] || return 0
  printf '%s:%s\n' "$report" "$(stat -f '%m' "$report" 2>/dev/null || echo 0)"
}

report_summary() {
  local report="$1"
  echo "### $(basename "$report")"
  echo
  if [[ "$report" == *.ips ]]; then
    python3 - "$report" <<'PY' 2>/dev/null || sed -n '1,80p' "$report"
import json
import sys

path = sys.argv[1]
with open(path, "r", encoding="utf-8", errors="replace") as handle:
    raw = handle.read()
decoder = json.JSONDecoder()
data, _ = decoder.raw_decode(raw)

def emit(label, value):
    if value not in (None, ""):
        print(f"- {label}: {value}")

emit("Incident", data.get("incident"))
emit("Timestamp", data.get("timestamp"))
emit("Process", data.get("procName"))
emit("Exception", data.get("exception", {}).get("type"))
emit("Termination", data.get("termination", {}).get("reason"))
emit("Signal", data.get("signal"))
threads = data.get("threads") or []
for thread in threads:
    if thread.get("triggered"):
        emit("Triggered Thread", thread.get("id"))
        frames = thread.get("frames") or []
        for frame in frames[:12]:
            image = frame.get("imageOffset") or frame.get("imageIndex") or "?"
            symbol = frame.get("symbol") or frame.get("symbolLocation") or frame.get("sourceFile") or "unknown"
            print(f"  - {image}: {symbol}")
        break
PY
  else
    awk '
      /^(Process:|Identifier:|Version:|Code Type:|Parent Process:|Date\/Time:|OS Version:|Report Version:|Exception Type:|Exception Codes:|Termination Reason:|Crashed Thread:|Thread [0-9]+ Crashed:)/ { print }
      /^Thread [0-9]+ Crashed:/ { crashed=1; print; next }
      crashed && /^[0-9]+/ { print; count++; if (count >= 16) exit }
    ' "$report"
  fi
  echo
}

append_event() {
  local reason="$1"
  printf '%s %s\n' "$(now_iso)" "$reason" >> "$EVENTS"
}

collect_incident() {
  local reason="$1"
  local stamp incident
  stamp="$(safe_stamp)"
  incident="$WATCH_DIR/incident-$stamp"
  mkdir -p "$incident"
  append_event "$reason -> $incident"

  {
    echo "# Conductor Crash Watch"
    echo
    echo "- Captured: $(now_iso)"
    echo "- Reason: $reason"
    echo "- Watch directory: $WATCH_DIR"
    echo
    echo "## Running Process"
    echo
    local pids
    pids="$(conductor_pids | tr '\n' ' ' | sed 's/[[:space:]]*$//')"
    if [[ -n "$pids" ]]; then
      ps -p "$(echo "$pids" | tr ' ' ',')" -o pid,ppid,stat,lstart,command 2>/dev/null || true
    else
      echo "No Conductor process is currently running."
    fi
    echo
    echo "## Recent Crash Reports"
    echo
    local found=0
    while IFS= read -r report; do
      [[ -n "$report" ]] || continue
      found=1
      cp -p "$report" "$incident/" 2>/dev/null || true
      report_summary "$report"
    done < <(latest_reports)
    if [[ "$found" == "0" ]]; then
      echo "No Conductor crash report found in ~/Library/Logs/DiagnosticReports."
      echo
    fi
    echo "## Watcher Events"
    echo
    tail -30 "$EVENTS" 2>/dev/null || true
  } > "$incident/summary.md"

  log show --last 10m \
    --predicate 'process == "Conductor" OR eventMessage CONTAINS[c] "Conductor" OR senderImagePath CONTAINS[c] "Conductor"' \
    --style compact > "$incident/system.log" 2>&1 || true

  cp "$incident/summary.md" "$SUMMARY"
  ln -sfn "$incident" "$WATCH_DIR/latest"
}

load_state() {
  LAST_PIDS=""
  LAST_REPORT_KEY=""
  if [[ -f "$STATE_FILE" ]]; then
    # shellcheck disable=SC1090
    source "$STATE_FILE"
  fi
}

save_state() {
  {
    printf 'LAST_PIDS=%q\n' "$LAST_PIDS"
    printf 'LAST_REPORT_KEY=%q\n' "$LAST_REPORT_KEY"
  } > "$STATE_FILE"
}

daemon() {
  echo $$ > "$PIDFILE"
  trap 'rm -f "$PIDFILE"' EXIT
  append_event "watcher-started pid=$$ interval=${INTERVAL}s"
  load_state
  if [[ ! -f "$STATE_FILE" ]]; then
    LAST_PIDS="$(conductor_pids | tr '\n' ' ' | sed 's/[[:space:]]*$//')"
    LAST_REPORT_KEY="$(latest_report_key)"
    save_state
  fi
  while true; do
    local current_pids current_key
    current_pids="$(conductor_pids | tr '\n' ' ' | sed 's/[[:space:]]*$//')"
    current_key="$(latest_report_key)"

    if [[ -n "$LAST_PIDS" && -z "$current_pids" ]]; then
      collect_incident "process-exited previous-pids=$LAST_PIDS"
    fi

    if [[ -n "$current_key" && "$current_key" != "$LAST_REPORT_KEY" ]]; then
      collect_incident "new-crash-report $current_key"
    fi

    LAST_PIDS="$current_pids"
    LAST_REPORT_KEY="$current_key"
    save_state
    sleep "$INTERVAL"
  done
}

start() {
  if [[ -f "$PIDFILE" ]] && kill -0 "$(cat "$PIDFILE")" 2>/dev/null; then
    echo "Conductor crash watcher is already running: pid $(cat "$PIDFILE")"
    return
  fi
  nohup "$0" daemon >> "$WATCH_LOG" 2>&1 &
  echo "Started Conductor crash watcher: pid $!"
  echo "Logs: $WATCH_DIR"
}

stop() {
  if [[ -f "$PIDFILE" ]] && kill -0 "$(cat "$PIDFILE")" 2>/dev/null; then
    kill "$(cat "$PIDFILE")" 2>/dev/null || true
    rm -f "$PIDFILE"
    echo "Stopped Conductor crash watcher."
  else
    echo "Conductor crash watcher is not running."
  fi
}

install() {
  mkdir -p "$(dirname "$PLIST")"
  cat > "$PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>$LABEL</string>
  <key>ProgramArguments</key>
  <array>
    <string>$ROOT/Scripts/watch-crashes.sh</string>
    <string>daemon</string>
  </array>
  <key>RunAtLoad</key>
  <true/>
  <key>KeepAlive</key>
  <true/>
  <key>StandardOutPath</key>
  <string>$WATCH_LOG</string>
  <key>StandardErrorPath</key>
  <string>$WATCH_LOG</string>
</dict>
</plist>
PLIST
  launchctl bootout "gui/$(id -u)" "$PLIST" >/dev/null 2>&1 || true
  launchctl bootstrap "gui/$(id -u)" "$PLIST"
  launchctl kickstart -k "gui/$(id -u)/$LABEL"
  echo "Installed Conductor crash watcher LaunchAgent."
  echo "Logs: $WATCH_DIR"
}

uninstall() {
  launchctl bootout "gui/$(id -u)" "$PLIST" >/dev/null 2>&1 || true
  rm -f "$PLIST"
  stop
  echo "Removed Conductor crash watcher LaunchAgent."
}

status() {
  echo "Watch directory: $WATCH_DIR"
  if [[ -f "$PIDFILE" ]] && kill -0 "$(cat "$PIDFILE")" 2>/dev/null; then
    echo "Watcher: running pid $(cat "$PIDFILE")"
  else
    echo "Watcher: not running"
  fi
  local pids
  pids="$(conductor_pids | tr '\n' ' ')"
  echo "Conductor pids: ${pids:-none}"
  echo "Latest summary: $SUMMARY"
  [[ -f "$SUMMARY" ]] && tail -40 "$SUMMARY"
}

case "${1:-}" in
  install) install ;;
  uninstall) uninstall ;;
  start) start ;;
  stop) stop ;;
  status) status ;;
  snapshot) collect_incident "manual-snapshot"; echo "Snapshot: $SUMMARY" ;;
  daemon) daemon ;;
  *) usage; exit 2 ;;
esac
