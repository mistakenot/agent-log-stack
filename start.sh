#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Preflight
if ! command -v docker &>/dev/null; then
  echo "ERROR: docker is not installed" >&2
  exit 1
fi

if ! docker compose version &>/dev/null 2>&1; then
  echo "ERROR: docker compose is not available" >&2
  exit 1
fi

if ! docker info &>/dev/null 2>&1; then
  echo "ERROR: Docker daemon is not running" >&2
  exit 1
fi

# Create .env from example if missing
if [[ ! -f .env ]]; then
  cp .env.example .env
  echo "Created .env from .env.example"
fi

# Start stack and wait for health checks
echo "Starting agent-logs stack..."
docker compose up -d --wait

# Read ports from env with defaults
VL_PORT="${VICTORIA_LOGS_PORT:-9428}"
VM_PORT="${VICTORIA_METRICS_PORT:-8428}"
PH_PORT="${PHOENIX_PORT:-6006}"
OTEL_HTTP="${OTEL_HTTP_PORT:-4318}"
OTEL_GRPC="${OTEL_GRPC_PORT:-4317}"

echo ""
echo "=== Agent Logs Stack ==="
echo "OTLP HTTP:       http://127.0.0.1:${OTEL_HTTP}  (logs: /v1/logs, traces: /v1/traces)"
echo "OTLP gRPC:       http://127.0.0.1:${OTEL_GRPC}"
echo "VictoriaLogs:    http://127.0.0.1:${VL_PORT}"
echo "VictoriaLogs UI: http://127.0.0.1:${VL_PORT}/select/vmui/"
echo "VictoriaMetrics: http://127.0.0.1:${VM_PORT}"
echo "Phoenix:         http://127.0.0.1:${PH_PORT}"
echo ""
echo "Send a test log:"
echo "  ./scripts/emit-log.sh --app test \"hello world\""
echo ""
echo "Query logs:"
echo "  curl -s 'http://127.0.0.1:${VL_PORT}/select/logsql/query' -d 'query={app=\"test\"} | limit 10'"
