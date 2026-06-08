#!/usr/bin/env bash
set -euo pipefail

# e2e.sh — Full end-to-end test runner for the agent-logs observability stack.
# Starts an isolated Docker Compose stack, emits logs, queries them, and tears down.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# --- Help ---

show_help() {
  cat <<'EOF'
Usage: e2e.sh [OPTIONS]

Run end-to-end tests for the agent-logs observability stack.

Starts an isolated Docker Compose stack, emits test logs via the log-generator,
queries VictoriaLogs/VictoriaMetrics/Phoenix, and validates results.

Options:
  --help    Show this help and exit

Environment variables:
  KEEP_STACK          Set to 1 to leave the Docker stack running after tests
  AGENT_LOGS_URL      OTLP collector URL (default: http://127.0.0.1:4318)
  VICTORIA_LOGS_URL   VictoriaLogs URL (default: http://127.0.0.1:9428)
  VICTORIA_METRICS_URL  VictoriaMetrics URL (default: http://127.0.0.1:8428)

Exit codes:
  0   All tests passed
  1   One or more tests failed or a prerequisite check failed
EOF
  exit 0
}

if [[ "${1:-}" == "--help" ]]; then
  show_help
fi

# --- Configuration ---

KEEP_STACK="${KEEP_STACK:-0}"
AGENT_LOGS_URL="${AGENT_LOGS_URL:-http://127.0.0.1:4318}"
VICTORIA_LOGS_URL="${VICTORIA_LOGS_URL:-http://127.0.0.1:9428}"
VICTORIA_METRICS_URL="${VICTORIA_METRICS_URL:-http://127.0.0.1:8428}"
PHOENIX_URL="http://127.0.0.1:6006"

# Generate unique run ID
E2E_RUN_ID="e2e-$(date +%s)-$(head -c 4 /dev/urandom | od -An -tx4 | tr -d ' ')"
SHORT_ID="$(echo "$E2E_RUN_ID" | tail -c 9)"
COMPOSE_PROJECT="agent-logs-e2e-${SHORT_ID}"

# Counters
PASS_COUNT=0
FAIL_COUNT=0
TOTAL_COUNT=0

# --- Output helpers ---

log() {
  echo "[e2e] $*"
}

log_section() {
  echo ""
  echo "=== $* ==="
}

pass() {
  PASS_COUNT=$((PASS_COUNT + 1))
  TOTAL_COUNT=$((TOTAL_COUNT + 1))
  echo "  PASS: $1"
}

fail() {
  FAIL_COUNT=$((FAIL_COUNT + 1))
  TOTAL_COUNT=$((TOTAL_COUNT + 1))
  echo "  FAIL: $1"
}

# --- Prerequisite checks ---

log_section "Prerequisites"

check_command() {
  local cmd="$1"
  local msg="${2:-$cmd is required but not found}"
  if ! command -v "$cmd" &>/dev/null; then
    echo "ERROR: $msg" >&2
    exit 1
  fi
  log "$cmd: found"
}

check_command docker "Docker is required. Install from https://docs.docker.com/get-docker/"
check_command curl "curl is required for HTTP requests"
check_command node "Node.js >= 18 is required"

# Check Docker Compose
if ! docker compose version &>/dev/null 2>&1; then
  echo "ERROR: docker compose is not available (requires Docker Compose V2)" >&2
  exit 1
fi
log "docker compose: found"

# Check Docker daemon
if ! docker info &>/dev/null 2>&1; then
  echo "ERROR: Docker daemon is not running" >&2
  exit 1
fi
log "docker daemon: running"

# Check Node.js version
NODE_VERSION=$(node --version | sed 's/v//' | cut -d. -f1)
if [[ "$NODE_VERSION" -lt 18 ]]; then
  echo "ERROR: Node.js >= 18 required (found v${NODE_VERSION})" >&2
  exit 1
fi
log "node: v${NODE_VERSION} (>= 18)"

# --- Port checks ---

log_section "Port availability"

PORTS_TO_CHECK=(
  "9428:VictoriaLogs"
  "4318:OTLP-HTTP"
  "8428:VictoriaMetrics"
  "6006:Phoenix"
  "4317:OTLP-gRPC"
  "9598:Vector-metrics"
)

PORTS_IN_USE=()
for entry in "${PORTS_TO_CHECK[@]}"; do
  port="${entry%%:*}"
  name="${entry#*:}"
  if ss -tlnp 2>/dev/null | grep -q ":${port} " || \
     netstat -tlnp 2>/dev/null | grep -q ":${port} "; then
    PORTS_IN_USE+=("$port ($name)")
  fi
done

if [[ ${#PORTS_IN_USE[@]} -gt 0 ]]; then
  echo "ERROR: The following ports are already in use:" >&2
  for p in "${PORTS_IN_USE[@]}"; do
    echo "  - $p" >&2
  done
  echo "" >&2
  echo "Suggestion: run ./scripts/down.sh to stop any existing stack" >&2
  exit 1
fi
log "All required ports are free"

# --- Stack startup ---

log_section "Starting stack"

log "Run ID: $E2E_RUN_ID"
log "Compose project: $COMPOSE_PROJECT"

# Ensure .env exists
if [[ ! -f "$PROJECT_DIR/.env" ]]; then
  cp "$PROJECT_DIR/.env.example" "$PROJECT_DIR/.env"
  log "Created .env from .env.example"
fi

# Cleanup function
cleanup() {
  local exit_code=$?
  if [[ "$KEEP_STACK" == "1" ]]; then
    log "KEEP_STACK=1: leaving stack running (project: $COMPOSE_PROJECT)"
    log "To stop: docker compose -p $COMPOSE_PROJECT -f $PROJECT_DIR/docker-compose.yml down -v"
  else
    log "Tearing down stack..."
    docker compose -p "$COMPOSE_PROJECT" -f "$PROJECT_DIR/docker-compose.yml" down -v 2>/dev/null || true
  fi
  exit $exit_code
}
trap cleanup EXIT

# Start compose stack
docker compose -p "$COMPOSE_PROJECT" -f "$PROJECT_DIR/docker-compose.yml" up -d 2>&1

# --- Wait for health ---

log_section "Waiting for services"

wait_for_health() {
  local name="$1"
  local url="$2"
  local max_attempts="${3:-60}"
  local attempt=0

  while [[ $attempt -lt $max_attempts ]]; do
    if curl -sf "$url" >/dev/null 2>&1; then
      log "$name: healthy"
      return 0
    fi
    attempt=$((attempt + 1))
    sleep 2
  done

  echo "ERROR: $name failed to become healthy after $((max_attempts * 2))s (url: $url)" >&2
  return 1
}

wait_for_health "VictoriaLogs" "${VICTORIA_LOGS_URL}/health" 45
wait_for_otlp() {
  local max_attempts=45
  local attempt=0
  local probe_payload='{"resourceLogs":[{"resource":{"attributes":[{"key":"app","value":{"stringValue":"_e2e_probe"}}]},"scopeLogs":[{"scope":{},"logRecords":[{"timeUnixNano":"0","body":{"stringValue":"health-probe"}}]}]}]}'
  while [[ $attempt -lt $max_attempts ]]; do
    if curl -sf -X POST "${AGENT_LOGS_URL}/v1/logs" \
         -H 'Content-Type: application/json' \
         -d "$probe_payload" >/dev/null 2>&1; then
      log "OTLP collector: healthy"
      return 0
    fi
    attempt=$((attempt + 1))
    sleep 2
  done
  echo "ERROR: OTLP collector failed to become healthy after $((max_attempts * 2))s (url: ${AGENT_LOGS_URL}/v1/logs)" >&2
  return 1
}
wait_for_otlp
wait_for_health "VictoriaMetrics" "${VICTORIA_METRICS_URL}/health" 45
wait_for_health "Phoenix" "${PHOENIX_URL}/healthz" 60

# Give vmagent time to start (no external health endpoint, but it depends on VictoriaMetrics)
sleep 3
log "vmagent: assumed healthy (depends on VictoriaMetrics)"

# --- Emit test logs ---

log_section "Emitting test logs"

log "Running log-generator (agent: e2e-agent)..."
node "$PROJECT_DIR/examples/log-generator/generate.js" \
  --run-id="$E2E_RUN_ID" \
  --agent-id=e2e-agent \
  --app=e2e-test

log "Running log-generator (agent: e2e-agent-2)..."
node "$PROJECT_DIR/examples/log-generator/generate.js" \
  --run-id="$E2E_RUN_ID" \
  --agent-id=e2e-agent-2 \
  --app=e2e-test

# --- Send OTLP trace to Phoenix ---

log_section "Sending OTLP trace"

TRACE_ID="$(printf '%032x' "$(date +%s%N)" 2>/dev/null || printf '%032x' "$(date +%s)000000000")"
SPAN_ID="$(printf '%016x' "$$")"

OTLP_PAYLOAD=$(cat <<OTLP_EOF
{
  "resourceSpans": [{
    "resource": {
      "attributes": [{
        "key": "service.name",
        "value": {"stringValue": "e2e-test-service"}
      }]
    },
    "scopeSpans": [{
      "scope": {"name": "e2e-test"},
      "spans": [{
        "traceId": "${TRACE_ID}",
        "spanId": "${SPAN_ID}",
        "name": "e2e-test-span-${E2E_RUN_ID}",
        "kind": 1,
        "startTimeUnixNano": "$(date +%s)000000000",
        "endTimeUnixNano": "$(date +%s)100000000",
        "attributes": [{
          "key": "e2e.run_id",
          "value": {"stringValue": "${E2E_RUN_ID}"}
        }],
        "status": {"code": 1}
      }]
    }]
  }]
}
OTLP_EOF
)

OTLP_HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" \
  -X POST "${AGENT_LOGS_URL}/v1/traces" \
  -H "Content-Type: application/json" \
  -d "$OTLP_PAYLOAD") || true

if [[ "$OTLP_HTTP_CODE" -ge 200 && "$OTLP_HTTP_CODE" -lt 300 ]]; then
  log "OTLP trace sent to collector (HTTP $OTLP_HTTP_CODE)"
else
  log "WARNING: OTLP collector returned non-2xx for traces (HTTP $OTLP_HTTP_CODE) — Vector may not forward traces"
fi

# --- Wait for ingestion ---

log "Waiting for ingestion (5s)..."
sleep 5

# --- Assertions ---

log_section "Running assertions"

assert_query() {
  local desc="$1"
  local query="$2"

  local result
  result=$(curl -sf "${VICTORIA_LOGS_URL}/select/logsql/query" \
    -d "query=${query}" \
    -d "limit=5" 2>/dev/null) || result=""

  if [[ -n "$result" ]]; then
    pass "$desc"
  else
    fail "$desc"
  fi
}

# Test log sources
assert_query "Backend logs ingested" \
  '{app="e2e-test",source="backend"} AND run_id:'${E2E_RUN_ID}''

assert_query "Browser logs ingested" \
  '{app="e2e-test",source="browser"} AND run_id:'${E2E_RUN_ID}''

assert_query "Database logs ingested" \
  '{app="e2e-test",source="database"} AND run_id:'${E2E_RUN_ID}''

assert_query "Process logs ingested" \
  '{app="e2e-test",source="process"} AND run_id:'${E2E_RUN_ID}''

# Test parallel agent distinguishable
assert_query "Parallel agent (e2e-agent-2) distinguishable" \
  '{app="e2e-test"} AND agent_id:e2e-agent-2 AND run_id:'${E2E_RUN_ID}''

# Test VictoriaMetrics has metrics
log ""
METRICS_RESULT=$(curl -sf "${VICTORIA_METRICS_URL}/api/v1/query" \
  --data-urlencode 'query=up' 2>/dev/null) || METRICS_RESULT=""

if echo "$METRICS_RESULT" | grep -q '"result":\[.\+\]'; then
  pass "VictoriaMetrics has 'up' metrics"
else
  # vmagent may not have scraped yet, retry after a brief wait
  sleep 10
  METRICS_RESULT=$(curl -sf "${VICTORIA_METRICS_URL}/api/v1/query" \
    --data-urlencode 'query=up' 2>/dev/null) || METRICS_RESULT=""
  if echo "$METRICS_RESULT" | grep -q '"result":\[.\+\]'; then
    pass "VictoriaMetrics has 'up' metrics (after retry)"
  else
    fail "VictoriaMetrics has 'up' metrics"
  fi
fi

# Test Phoenix health
PHOENIX_HEALTH=$(curl -sf -o /dev/null -w "%{http_code}" "${PHOENIX_URL}/healthz" 2>/dev/null) || PHOENIX_HEALTH="000"
if [[ "$PHOENIX_HEALTH" == "200" ]]; then
  pass "Phoenix healthz returns 200"
else
  fail "Phoenix healthz returns 200 (got $PHOENIX_HEALTH)"
fi

# --- Diagnostics on failure ---

if [[ $FAIL_COUNT -gt 0 ]]; then
  log_section "Diagnostics (failures detected)"
  echo ""
  echo "--- Container status ---"
  docker compose -p "$COMPOSE_PROJECT" -f "$PROJECT_DIR/docker-compose.yml" ps 2>/dev/null || true
  echo ""
  echo "--- Recent logs (tail 20 per service) ---"
  docker compose -p "$COMPOSE_PROJECT" -f "$PROJECT_DIR/docker-compose.yml" logs --tail=20 2>/dev/null || true
fi

# --- Summary ---

log_section "Summary"

echo ""
echo "  Run ID:  $E2E_RUN_ID"
echo "  Total:   $TOTAL_COUNT"
echo "  Passed:  $PASS_COUNT"
echo "  Failed:  $FAIL_COUNT"
echo ""

if [[ $FAIL_COUNT -eq 0 ]]; then
  echo "RESULT: PASS"
  exit 0
else
  echo "RESULT: FAIL"
  exit 1
fi
