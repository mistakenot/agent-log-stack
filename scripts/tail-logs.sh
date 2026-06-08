#!/usr/bin/env bash
set -euo pipefail

VICTORIA_LOGS_URL="${VICTORIA_LOGS_URL:-http://127.0.0.1:9428}"
VERBOSE=0
TIMEOUT=""

usage() {
  cat <<'EOF'
Usage: tail-logs.sh [OPTIONS] <logsql-query>

Live-tail logs from VictoriaLogs using the /select/logsql/tail streaming API.

Arguments:
  <logsql-query>    LogsQL filter expression (required)

Options:
  --timeout SECS    Maximum tail duration in seconds (passed to curl --max-time)
  --verbose         Print the API URL to stderr before streaming
  --help            Show this help message and exit

Environment:
  VICTORIA_LOGS_URL   Base URL for VictoriaLogs (default: http://127.0.0.1:9428)

Examples:
  tail-logs.sh '{app="myapp"}'
  tail-logs.sh --verbose '{source="backend"}'
  tail-logs.sh --timeout 60 '{level="error"}'
EOF
}

# Parse arguments
QUERY=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --help)
      usage
      exit 0
      ;;
    --verbose)
      VERBOSE=1
      shift
      ;;
    --timeout)
      if [[ -z "${2:-}" ]]; then
        echo "error: --timeout requires a value" >&2
        exit 1
      fi
      TIMEOUT="$2"
      shift 2
      ;;
    -*)
      echo "error: unknown option: $1" >&2
      echo "Run with --help for usage." >&2
      exit 1
      ;;
    *)
      if [[ -z "$QUERY" ]]; then
        QUERY="$1"
      else
        echo "error: unexpected argument: $1" >&2
        exit 1
      fi
      shift
      ;;
  esac
done

if [[ -z "$QUERY" ]]; then
  echo "error: logsql query argument is required" >&2
  echo "Run with --help for usage." >&2
  exit 1
fi

# Build the URL with query parameter
ENCODED_QUERY=$(python3 -c "import urllib.parse; print(urllib.parse.quote('''$QUERY'''))" 2>/dev/null || printf '%s' "$QUERY" | jq -sRr @uri 2>/dev/null || printf '%s' "$QUERY")
API_URL="${VICTORIA_LOGS_URL}/select/logsql/tail?query=${ENCODED_QUERY}"

if [[ "$VERBOSE" -eq 1 ]]; then
  echo "API URL: ${API_URL}" >&2
fi

# Trap SIGINT for clean exit
cleanup() {
  exit 0
}
trap cleanup SIGINT SIGTERM

# Build curl command
CURL_ARGS=(-sS -N --fail-with-body)
if [[ -n "$TIMEOUT" ]]; then
  CURL_ARGS+=(--max-time "$TIMEOUT")
fi

exec curl "${CURL_ARGS[@]}" "$API_URL"
