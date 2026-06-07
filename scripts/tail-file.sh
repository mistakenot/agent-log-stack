#!/usr/bin/env bash
set -euo pipefail

# --- Help ---
show_help() {
  cat <<'EOF'
Usage: tail-file.sh [OPTIONS] [FILE]

Ship lines from a file (tail -F) or stdin to Vector with metadata enrichment.

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
  AGENT_LOGS_URL      Vector ingest base URL (default: http://127.0.0.1:8688)
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
AGENT_LOGS_URL="${AGENT_LOGS_URL:-http://127.0.0.1:8688}"
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

# --- Determine ingest path based on source ---
case "$SOURCE" in
  browser)  INGEST_PATH="/ingest/browser" ;;
  database) INGEST_PATH="/ingest/db" ;;
  backend)  INGEST_PATH="/ingest/logs" ;;
  *)        INGEST_PATH="/ingest/process" ;;
esac

INGEST_URL="${AGENT_LOGS_URL}${INGEST_PATH}"

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

# --- Send a single line as a log event ---
send_line() {
  local line="$1"
  local ts
  ts="$(date -u +%Y-%m-%dT%H:%M:%S.%3NZ 2>/dev/null || date -u +%Y-%m-%dT%H:%M:%SZ)"

  local payload
  payload=$(printf '%s' "{}" | jq -c \
    --arg message "$line" \
    --arg timestamp "$ts" \
    --arg level "info" \
    --arg source "$SOURCE" \
    --arg app "$APP" \
    --arg service "$SERVICE" \
    --arg agent_id "$AGENT_ID_VAL" \
    --arg run_id "$RUN_ID_VAL" \
    --arg worktree "$WORKTREE_VAL" \
    --arg log_file "$LOG_FILE" \
    --arg process_name "$PROCESS_NAME" \
    --argjson pid "$PROCESS_PID" \
    '{
      message: $message,
      timestamp: $timestamp,
      level: $level,
      source: $source,
      app: $app,
      service: $service,
      agent_id: $agent_id,
      run_id: $run_id,
      worktree: $worktree,
      log_file: $log_file,
      process_name: $process_name,
      pid: $pid
    }')

  curl -s -o /dev/null -X POST "$INGEST_URL" \
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
