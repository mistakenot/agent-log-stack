#!/usr/bin/env bash
set -euo pipefail

# --- Help ---
show_help() {
  cat <<'EOF'
Usage: tail-file.sh [OPTIONS] [FILE]

Ship lines from a file (tail -F) or stdin to an OTLP HTTP collector as log
records. Each line becomes one OTLP logRecord POSTed to /v1/logs.

If FILE is given, tail it with tail -F semantics (follows rotation).
If no FILE and stdin is not a terminal, read stdin line by line until EOF.

Options:
  --app NAME          Application name (default: "unknown")
  --service NAME      Service name (default: "unknown")
  --source NAME       Log source category (default: "process")
  --agent-id ID       Agent identifier (default: $AGENT_ID or hostname)
  --run-id ID         Run identifier (default: $RUN_ID or <timestamp>-<pid>)
  --worktree NAME     Worktree/branch name (default: $WORKTREE or git branch or cwd basename)
  --help              Show this help message

Environment variables:
  AGENT_LOGS_URL      OTLP HTTP base URL (default: http://127.0.0.1:4318)
  AGENT_ID            Default agent identifier
  RUN_ID              Default run identifier
  WORKTREE            Default worktree name

Examples:
  tail-file.sh --app myapp /var/log/myapp.log
  some-command | tail-file.sh --app myapp --service worker
  tail-file.sh --app myapp --source backend /tmp/app.log
EOF
  exit 0
}

# --- Defaults ---
AGENT_LOGS_URL="${AGENT_LOGS_URL:-http://127.0.0.1:4318}"
APP="unknown"
SERVICE="unknown"
SOURCE="process"
AGENT_ID_VAL="${AGENT_ID:-$(hostname 2>/dev/null || echo "unknown")}"
RUN_ID_VAL="${RUN_ID:-$(date -u +%Y%m%dT%H%M%S)-$$}"
WORKTREE_VAL="${WORKTREE:-}"
FILE_PATH=""

# --- Parse arguments ---
while [[ $# -gt 0 ]]; do
  case "$1" in
    --help)
      show_help
      ;;
    --app)
      APP="$2"; shift 2
      ;;
    --service)
      SERVICE="$2"; shift 2
      ;;
    --source)
      SOURCE="$2"; shift 2
      ;;
    --agent-id)
      AGENT_ID_VAL="$2"; shift 2
      ;;
    --run-id)
      RUN_ID_VAL="$2"; shift 2
      ;;
    --worktree)
      WORKTREE_VAL="$2"; shift 2
      ;;
    -*)
      echo "error: unknown option: $1" >&2
      echo "Run with --help for usage." >&2
      exit 1
      ;;
    *)
      FILE_PATH="$1"; shift
      ;;
  esac
done

# --- Derive worktree default ---
if [[ -z "$WORKTREE_VAL" ]]; then
  WORKTREE_VAL="$(git rev-parse --abbrev-ref HEAD 2>/dev/null || basename "$(pwd)")"
fi

# --- OTLP endpoint ---
OTLP_URL="${AGENT_LOGS_URL}/v1/logs"

# --- Determine process name and PID ---
PROCESS_PID=$$
if [[ -n "$FILE_PATH" ]]; then
  PROCESS_NAME="tail-file"
  LOG_FILE="$FILE_PATH"
else
  PROCESS_NAME="stdin"
  LOG_FILE="stdin"
fi

# --- Signal handling for clean exit ---
TAIL_PID=""
cleanup() {
  if [[ -n "$TAIL_PID" ]]; then
    kill "$TAIL_PID" 2>/dev/null || true
    wait "$TAIL_PID" 2>/dev/null || true
  fi
  exit 0
}
trap cleanup SIGINT SIGTERM

# --- Send a single line as an OTLP log record ---
send_line() {
  local line="$1"
  local time_unix_nano
  time_unix_nano="$(date +%s)000000000"

  local payload
  payload=$(jq -n -c \
    --arg service_name "$SERVICE" \
    --arg app "$APP" \
    --arg source "$SOURCE" \
    --arg agent_id "$AGENT_ID_VAL" \
    --arg run_id "$RUN_ID_VAL" \
    --arg worktree "$WORKTREE_VAL" \
    --arg log_file "$LOG_FILE" \
    --arg process_name "$PROCESS_NAME" \
    --argjson pid "$PROCESS_PID" \
    --arg time_unix_nano "$time_unix_nano" \
    --arg body "$line" \
    '{
      "resourceLogs": [{
        "resource": {
          "attributes": [
            {"key": "service.name", "value": {"stringValue": $service_name}},
            {"key": "app", "value": {"stringValue": $app}}
          ]
        },
        "scopeLogs": [{
          "scope": {},
          "logRecords": [{
            "timeUnixNano": $time_unix_nano,
            "severityText": "INFO",
            "severityNumber": 9,
            "body": {"stringValue": $body},
            "attributes": [
              {"key": "source", "value": {"stringValue": $source}},
              {"key": "agent_id", "value": {"stringValue": $agent_id}},
              {"key": "run_id", "value": {"stringValue": $run_id}},
              {"key": "worktree", "value": {"stringValue": $worktree}},
              {"key": "log_file", "value": {"stringValue": $log_file}},
              {"key": "process_name", "value": {"stringValue": $process_name}},
              {"key": "pid", "value": {"intValue": $pid}}
            ]
          }]
        }]
      }]
    }')

  curl -s -o /dev/null -X POST "$OTLP_URL" \
    -H 'Content-Type: application/json' \
    -d "$payload" || true
}

# --- Main: file mode or stdin mode ---
if [[ -n "$FILE_PATH" ]]; then
  # File mode: use tail -F to follow with rotation handling
  if [[ ! -e "$FILE_PATH" ]]; then
    echo "error: file not found: $FILE_PATH" >&2
    echo "Waiting for file to appear..." >&2
  fi

  # Start tail -F in background and read from it
  exec 3< <(tail -F "$FILE_PATH" 2>/dev/null)
  TAIL_PID=$!

  while IFS= read -r line <&3; do
    [[ -z "$line" ]] && continue
    send_line "$line"
  done
else
  # Stdin mode: require piped input
  if [[ -t 0 ]]; then
    echo "error: no file specified and stdin is a terminal" >&2
    echo "Run with --help for usage." >&2
    exit 1
  fi

  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    send_line "$line"
  done
fi
