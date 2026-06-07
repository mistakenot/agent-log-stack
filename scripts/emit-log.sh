#!/usr/bin/env bash
set -euo pipefail

# emit-log.sh — Send a log event via OTLP HTTP to the Vector collector.

show_help() {
  cat <<'EOF'
Usage: emit-log.sh [OPTIONS] [MESSAGE]

Send a log event via OTLP HTTP (/v1/logs) to the Vector collector.

If MESSAGE is not provided as a positional argument and stdin is not a
terminal, the message is read from stdin.

Options:
  --app NAME          Application name (required field, no default)
  --service NAME      Service name (optional)
  --source NAME       Log source: backend, browser, database, process
                      (default: backend)
  --level LEVEL       Log level: trace, debug, info, warn, error, fatal
                      (default: info)
  --agent-id ID       Agent identifier
                      (default: $AGENT_ID or hostname)
  --run-id ID         Run identifier
                      (default: $RUN_ID or <timestamp>-<pid>)
  --worktree PATH     Worktree identifier
                      (default: $WORKTREE or git branch or cwd basename)
  --screen-id ID      Screen identifier (for browser source)
  --verbose           Print request URL to stderr
  --help              Show this help and exit

Environment variables:
  AGENT_LOGS_URL      Base URL for OTLP HTTP ingest (default: http://127.0.0.1:4318)
  AGENT_ID            Default agent identifier
  RUN_ID              Default run identifier
  WORKTREE            Default worktree identifier

Examples:
  emit-log.sh --app myapp "Server started on port 3000"
  echo "batch message" | emit-log.sh --app myapp --level warn
  emit-log.sh --app myapp --source browser --screen-id checkout "click event"
EOF
  exit 0
}

# Defaults
source_val="backend"
level_val="info"
app_val=""
service_val=""
agent_id_val=""
run_id_val=""
worktree_val=""
screen_id_val=""
verbose=false
message=""

# Parse arguments
positional_args=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --help)
      show_help
      ;;
    --app)
      app_val="$2"; shift 2
      ;;
    --service)
      service_val="$2"; shift 2
      ;;
    --source)
      source_val="$2"; shift 2
      ;;
    --level)
      level_val="$2"; shift 2
      ;;
    --agent-id)
      agent_id_val="$2"; shift 2
      ;;
    --run-id)
      run_id_val="$2"; shift 2
      ;;
    --worktree)
      worktree_val="$2"; shift 2
      ;;
    --screen-id)
      screen_id_val="$2"; shift 2
      ;;
    --verbose)
      verbose=true; shift
      ;;
    --)
      shift; positional_args+=("$@"); break
      ;;
    -*)
      echo "emit-log.sh: unknown option: $1" >&2
      echo "Try 'emit-log.sh --help' for usage." >&2
      exit 1
      ;;
    *)
      positional_args+=("$1"); shift
      ;;
  esac
done

# Determine message from positional args or stdin
if [[ ${#positional_args[@]} -gt 0 ]]; then
  message="${positional_args[*]}"
elif [[ ! -t 0 ]]; then
  message="$(cat)"
else
  echo "emit-log.sh: no message provided (pass as argument or pipe via stdin)" >&2
  exit 1
fi

# Auto-derive defaults
if [[ -z "$agent_id_val" ]]; then
  agent_id_val="${AGENT_ID:-$(hostname)}"
fi

if [[ -z "$run_id_val" ]]; then
  run_id_val="${RUN_ID:-$(date +%s)-$$}"
fi

if [[ -z "$worktree_val" ]]; then
  if [[ -n "${WORKTREE:-}" ]]; then
    worktree_val="$WORKTREE"
  elif git rev-parse --abbrev-ref HEAD >/dev/null 2>&1; then
    worktree_val="$(git rev-parse --abbrev-ref HEAD)"
  else
    worktree_val="$(basename "$PWD")"
  fi
fi

# Map severity text and number
sev_text=$(echo "$level_val" | tr "[:lower:]" "[:upper:]")
case "$level_val" in
  trace) sev_num=1 ;;
  debug) sev_num=5 ;;
  info)  sev_num=9 ;;
  warn)  sev_num=13 ;;
  error) sev_num=17 ;;
  fatal) sev_num=21 ;;
  *)     sev_num=9 ;;
esac

# Build URL
base_url="${AGENT_LOGS_URL:-http://127.0.0.1:4318}"
url="${base_url}/v1/logs"

if [[ "$verbose" == "true" ]]; then
  echo "POST $url" >&2
fi

# Build resource attributes array
res_attrs='[]'
if [[ -n "$service_val" ]]; then
  res_attrs=$(jq -n --arg svc "$service_val" '[{"key":"service.name","value":{"stringValue":$svc}}]')
fi
if [[ -n "$app_val" ]]; then
  res_attrs=$(echo "$res_attrs" | jq --arg app "$app_val" '. + [{"key":"app","value":{"stringValue":$app}}]')
fi

# Build log record attributes array (only non-empty values)
log_attrs='[]'
if [[ -n "$source_val" ]]; then
  log_attrs=$(echo "$log_attrs" | jq --arg v "$source_val" '. + [{"key":"source","value":{"stringValue":$v}}]')
fi
if [[ -n "$agent_id_val" ]]; then
  log_attrs=$(echo "$log_attrs" | jq --arg v "$agent_id_val" '. + [{"key":"agent_id","value":{"stringValue":$v}}]')
fi
if [[ -n "$run_id_val" ]]; then
  log_attrs=$(echo "$log_attrs" | jq --arg v "$run_id_val" '. + [{"key":"run_id","value":{"stringValue":$v}}]')
fi
if [[ -n "$worktree_val" ]]; then
  log_attrs=$(echo "$log_attrs" | jq --arg v "$worktree_val" '. + [{"key":"worktree","value":{"stringValue":$v}}]')
fi
if [[ -n "$screen_id_val" ]]; then
  log_attrs=$(echo "$log_attrs" | jq --arg v "$screen_id_val" '. + [{"key":"screen_id","value":{"stringValue":$v}}]')
fi

# Timestamp as epoch nanoseconds (string)
time_unix_nano="$(date +%s)000000000"

# Assemble OTLP JSON payload
json_payload=$(jq -n \
  --argjson res_attrs "$res_attrs" \
  --argjson log_attrs "$log_attrs" \
  --arg tn "$time_unix_nano" \
  --arg st "$sev_text" \
  --argjson sn "$sev_num" \
  --arg body "$message" \
  '{
    resourceLogs: [{
      resource: { attributes: $res_attrs },
      scopeLogs: [{
        scope: {},
        logRecords: [{
          timeUnixNano: $tn,
          severityText: $st,
          severityNumber: $sn,
          body: { stringValue: $body },
          attributes: $log_attrs
        }]
      }]
    }]
  }')

# Send request
http_code=$(curl -s -o /dev/stdout -w '\n%{http_code}' \
  -X POST "$url" \
  -H 'Content-Type: application/json' \
  -d "$json_payload" 2>&1) || {
  exit_code=$?
  echo "emit-log.sh: curl failed with exit code $exit_code" >&2
  echo "emit-log.sh: url=$url" >&2
  exit $exit_code
}

# Extract HTTP status code (last line)
response_body="$(echo "$http_code" | head -n -1)"
status_code="$(echo "$http_code" | tail -n 1)"

# Print response body if non-empty
if [[ -n "$response_body" ]]; then
  echo "$response_body"
fi

# Check for HTTP errors
if [[ "$status_code" -ge 400 ]] 2>/dev/null; then
  echo "emit-log.sh: HTTP $status_code from $url" >&2
  exit 1
fi
