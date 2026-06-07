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
VI_PORT="${VECTOR_INGEST_PORT:-8688}"
VM_PORT="${VICTORIA_METRICS_PORT:-8428}"
PH_PORT="${PHOENIX_PORT:-6006}"

echo ""
echo "=== Agent Logs Stack ==="
echo "VictoriaLogs:    http://127.0.0.1:${VL_PORT}"
echo "VictoriaLogs UI: http://127.0.0.1:${VL_PORT}/select/vmui/"
echo "Vector Ingest:   http://127.0.0.1:${VI_PORT}"
echo "VictoriaMetrics: http://127.0.0.1:${VM_PORT}"
echo "Phoenix:         http://127.0.0.1:${PH_PORT}"
echo "Phoenix OTLP:    http://127.0.0.1:${PH_PORT}/v1/traces"
echo ""
echo "Send a test log:"
echo "  curl -s -X POST http://127.0.0.1:${VI_PORT}/ingest/logs -H 'Content-Type: application/json' -d '{\"message\":\"hello\",\"app\":\"test\"}'"
echo ""
echo "Query logs:"
echo "  curl -s 'http://127.0.0.1:${VL_PORT}/select/logsql/query' -d 'query={app=\"test\"} | limit 10'"
