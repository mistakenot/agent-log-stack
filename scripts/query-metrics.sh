#!/usr/bin/env bash
set -euo pipefail

# query-metrics.sh — CLI wrapper around VictoriaMetrics PromQL/MetricsQL API

VICTORIA_METRICS_URL="${VICTORIA_METRICS_URL:-http://127.0.0.1:8428}"
VERBOSE=0
TIMEOUT=10
EXPECT=0

usage() {
  cat <<'EOF'
Usage: query-metrics.sh [OPTIONS] <promql-query>

Query VictoriaMetrics using PromQL/MetricsQL.

Arguments:
  <promql-query>    PromQL or MetricsQL expression (required)

Options:
  --help            Show this help message and exit
  --verbose         Print the full API URL to stderr
  --timeout <sec>   HTTP request timeout in seconds (default: 10)
  --expect          Assertion mode: exit 0 if query returns data, exit 1 otherwise

Environment:
  VICTORIA_METRICS_URL  Base URL (default: http://127.0.0.1:8428)

Examples:
  query-metrics.sh 'up'
  query-metrics.sh --verbose 'rate(http_requests_total[5m])'
  query-metrics.sh --expect 'up{job="vector"}'
  query-metrics.sh --timeout 30 'count(process_cpu_seconds_total)'
EOF
  exit 0
}

# Parse arguments
QUERY=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --help)
      usage
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
    --expect)
      EXPECT=1
      shift
      ;;
    -*)
      echo "error: unknown option: $1" >&2
      echo "Run with --help for usage." >&2
      exit 1
      ;;
    *)
      if [[ -n "$QUERY" ]]; then
        echo "error: multiple positional arguments provided; query must be a single argument" >&2
        exit 1
      fi
      QUERY="$1"
      shift
      ;;
  esac
done

if [[ -z "$QUERY" ]]; then
  echo "error: query argument is required" >&2
  echo "Run with --help for usage." >&2
  exit 1
fi

# URL-encode the query
encoded_query=$(python3 -c "import urllib.parse, sys; print(urllib.parse.quote(sys.argv[1]))" "$QUERY" 2>/dev/null || printf '%s' "$QUERY" | jq -sRr @uri 2>/dev/null || printf '%s' "$QUERY")

api_url="${VICTORIA_METRICS_URL}/api/v1/query?query=${encoded_query}"

if [[ "$VERBOSE" -eq 1 ]]; then
  echo "API URL: ${api_url}" >&2
fi

# Execute the query
http_code_file=$(mktemp)
trap 'rm -f "$http_code_file"' EXIT

response=$(curl -s -w "%{http_code}" --max-time "$TIMEOUT" -o >(cat) "$api_url" 2>/dev/null) || {
  exit_code=$?
  echo "error: request failed for query='${QUERY}' endpoint='${VICTORIA_METRICS_URL}' (curl exit code: ${exit_code})" >&2
  exit 1
}

# Extract HTTP status code (last 3 characters)
http_status="${response: -3}"
body="${response:0:${#response}-3}"

# Check for HTTP errors
if [[ "$http_status" -lt 200 || "$http_status" -ge 300 ]]; then
  excerpt="${body:0:200}"
  echo "error: HTTP ${http_status} for query='${QUERY}' endpoint='${VICTORIA_METRICS_URL}'" >&2
  echo "response: ${excerpt}" >&2
  if [[ "$EXPECT" -eq 1 ]]; then
    exit 1
  fi
  exit 1
fi

# In expect mode, check if data is present
if [[ "$EXPECT" -eq 1 ]]; then
  # Check status field and whether result array is non-empty
  status=$(printf '%s' "$body" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    if data.get('status') != 'success':
        sys.exit(1)
    result = data.get('data', {}).get('result', [])
    if len(result) > 0:
        sys.exit(0)
    else:
        sys.exit(1)
except Exception:
    sys.exit(1)
" 2>/dev/null) && {
    printf '%s\n' "$body"
    exit 0
  } || {
    printf '%s\n' "$body"
    exit 1
  }
fi

# Default: print JSON response to stdout
printf '%s\n' "$body"
