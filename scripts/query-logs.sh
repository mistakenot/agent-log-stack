#!/usr/bin/env bash
set -euo pipefail

# query-logs.sh — CLI wrapper around VictoriaLogs LogsQL HTTP API

VICTORIA_LOGS_URL="${VICTORIA_LOGS_URL:-http://127.0.0.1:9428}"

# Defaults
LIMIT=50
SINCE="15m"
TIMEOUT=30
VERBOSE=false
PRETTY=false
EXPECT=false
QUERY=""

usage() {
  cat <<'EOF'
Usage: query-logs.sh [OPTIONS] <LOGSQL_QUERY>

Query VictoriaLogs using LogsQL via the HTTP API.

Arguments:
  LOGSQL_QUERY          Raw LogsQL query string (required)

Options:
  --since DURATION      Time window to query (default: 15m)
                        Format: Nm (minutes), Nh (hours), Nd (days)
  --limit N             Maximum number of results (default: 50)
  --timeout SECONDS     HTTP request timeout in seconds (default: 30)
  --verbose             Print API URL to stderr
  --pretty              Pretty-print output (pipe through jq if available)
  --expect              Assertion mode: exit 0 if results found, exit 1 if none
  --help                Show this help message

Environment:
  VICTORIA_LOGS_URL     VictoriaLogs base URL (default: http://127.0.0.1:9428)

Examples:
  query-logs.sh '{app="myapp"}'
  query-logs.sh --since 1h --limit 100 '{source="backend"} | level:error'
  query-logs.sh --expect '{app="myapp",source="backend"} | error'
  query-logs.sh --pretty '{app="myapp"}' | less
EOF
}

# Parse duration string (Nm, Nh, Nd) to seconds
parse_duration() {
  local input="$1"
  local num="${input%[mhd]}"
  local unit="${input: -1}"

  if ! [[ "$num" =~ ^[0-9]+$ ]]; then
    echo "Error: invalid duration format: $input (expected Nm, Nh, or Nd)" >&2
    exit 2
  fi

  case "$unit" in
    m) echo $((num * 60)) ;;
    h) echo $((num * 3600)) ;;
    d) echo $((num * 86400)) ;;
    *) echo "Error: invalid duration unit: $unit (expected m, h, or d)" >&2; exit 2 ;;
  esac
}

# Parse arguments
while [[ $# -gt 0 ]]; do
  case "$1" in
    --help)
      usage
      exit 0
      ;;
    --since)
      SINCE="$2"
      shift 2
      ;;
    --limit)
      LIMIT="$2"
      shift 2
      ;;
    --timeout)
      TIMEOUT="$2"
      shift 2
      ;;
    --verbose)
      VERBOSE=true
      shift
      ;;
    --pretty)
      PRETTY=true
      shift
      ;;
    --expect)
      EXPECT=true
      shift
      ;;
    -*)
      echo "Error: unknown option: $1" >&2
      echo "Run with --help for usage information." >&2
      exit 2
      ;;
    *)
      if [[ -z "$QUERY" ]]; then
        QUERY="$1"
      else
        echo "Error: unexpected positional argument: $1" >&2
        exit 2
      fi
      shift
      ;;
  esac
done

# Validate required arguments
if [[ -z "$QUERY" ]]; then
  echo "Error: LOGSQL_QUERY is required." >&2
  echo "Run with --help for usage information." >&2
  exit 2
fi

# Compute time range
SINCE_SECONDS=$(parse_duration "$SINCE")
END_TIME=$(date -u +%s)
START_TIME=$((END_TIME - SINCE_SECONDS))
START_ISO=$(date -u -d "@$START_TIME" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -r "$START_TIME" +%Y-%m-%dT%H:%M:%SZ)
END_ISO=$(date -u -d "@$END_TIME" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -r "$END_TIME" +%Y-%m-%dT%H:%M:%SZ)

# Build query with time filter
FULL_QUERY="${QUERY} | _time:[${START_ISO}, ${END_ISO}]"

# Build API URL
API_URL="${VICTORIA_LOGS_URL}/select/logsql/query"

if [[ "$VERBOSE" == "true" ]]; then
  echo "API URL: ${API_URL}" >&2
  echo "Query: ${FULL_QUERY}" >&2
  echo "Limit: ${LIMIT}" >&2
fi

# Execute query via curl
HTTP_RESPONSE=$(mktemp)
HTTP_BODY=$(mktemp)
trap 'rm -f "$HTTP_RESPONSE" "$HTTP_BODY"' EXIT

HTTP_CODE=$(curl -s -o "$HTTP_BODY" -w "%{http_code}" \
  --max-time "$TIMEOUT" \
  -X POST "$API_URL" \
  -d "query=${FULL_QUERY}" \
  -d "limit=${LIMIT}" \
  2>"$HTTP_RESPONSE") || {
  CURL_EXIT=$?
  echo "Error: curl failed (exit code $CURL_EXIT)" >&2
  echo "  Query: ${FULL_QUERY}" >&2
  echo "  Endpoint: ${API_URL}" >&2
  if [[ -s "$HTTP_RESPONSE" ]]; then
    echo "  Details: $(head -c 200 "$HTTP_RESPONSE")" >&2
  fi
  exit 1
}

# Check HTTP status
if [[ "$HTTP_CODE" -lt 200 || "$HTTP_CODE" -ge 300 ]]; then
  EXCERPT=$(head -c 200 "$HTTP_BODY" | tr '\n' ' ')
  echo "Error: HTTP ${HTTP_CODE} from VictoriaLogs" >&2
  echo "  Query: ${FULL_QUERY}" >&2
  echo "  Endpoint: ${API_URL}" >&2
  echo "  Response: ${EXCERPT}" >&2
  exit 1
fi

# Handle --expect mode
if [[ "$EXPECT" == "true" ]]; then
  if [[ -s "$HTTP_BODY" ]]; then
    exit 0
  else
    echo "No results found." >&2
    echo "  Query: ${FULL_QUERY}" >&2
    echo "  Endpoint: ${API_URL}" >&2
    exit 1
  fi
fi

# Output results
if [[ ! -s "$HTTP_BODY" ]]; then
  exit 0
fi

if [[ "$PRETTY" == "true" ]]; then
  if command -v jq &>/dev/null; then
    # Process each NDJSON line through jq
    while IFS= read -r line; do
      echo "$line" | jq .
    done < "$HTTP_BODY"
  else
    cat "$HTTP_BODY"
  fi
else
  cat "$HTTP_BODY"
fi
