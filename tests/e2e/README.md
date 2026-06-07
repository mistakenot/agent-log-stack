# E2E Tests

End-to-end tests for the agent-logs observability stack.

## Running

```bash
./scripts/e2e.sh
```

## What it tests

1. Stack startup (VictoriaLogs, Vector, VictoriaMetrics, vmagent, Phoenix)
2. Log ingestion across all sources (backend, browser, database, process)
3. Log querying via VictoriaLogs LogsQL API
4. Multi-agent context isolation (parallel agent IDs are distinguishable)
5. Metrics collection via VictoriaMetrics
6. OTLP trace ingestion via Phoenix

## Environment variables

| Variable | Default | Description |
|----------|---------|-------------|
| `KEEP_STACK` | `0` | Set to `1` to leave Docker stack running after tests |
| `AGENT_LOGS_URL` | `http://127.0.0.1:8688` | Vector ingest base URL |
| `VICTORIA_LOGS_URL` | `http://127.0.0.1:9428` | VictoriaLogs query URL |
| `VICTORIA_METRICS_URL` | `http://127.0.0.1:8428` | VictoriaMetrics query URL |

## Test fixtures

Test fixtures and helper data live in this directory. The log-generator
(`examples/log-generator/generate.js`) produces deterministic logs with
unique markers per run, making assertions reliable.
