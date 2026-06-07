# Agent Logs

Local observability stack for AI coding agents. Collects logs, metrics, and traces from apps and runtimes the agent is driving.

## Quick Start

```bash
git clone <repo-url> && cd agent-logs
./start.sh
# Stack is ready. Ingest on :8688, query on :9428, metrics on :8428, traces on :6006.
```

## Architecture

```
                         +-------------------+
                         |   Your App/Agent  |
                         +-------------------+
                                  |
                   POST /ingest/* (JSON)
                                  v
                      +-----------------------+
                      |  Vector (8688)        |
                      |  HTTP ingest + VRL    |
                      |  normalize transform  |
                      +-----------------------+
                                  |
                    /insert/jsonline (gzip)
                                  v
                      +-----------------------+
                      | VictoriaLogs (9428)   |
                      | LogsQL query API      |
                      +-----------------------+

    vmagent scrapes /metrics from: vector, victoria-logs, victoria-metrics, phoenix
                                  |
                                  v
                      +-----------------------+
                      | VictoriaMetrics (8428)|
                      | PromQL query API      |
                      +-----------------------+

    Instrumented app ---> OTLP HTTP/gRPC
                                  |
                                  v
                      +-----------------------+
                      | Phoenix (6006/4317)   |
                      | Trace UI + collector  |
                      +-----------------------+
```

## Port Reference

| Service          | Port | Purpose                              |
|------------------|------|--------------------------------------|
| Vector           | 8688 | HTTP log ingest (all `/ingest/*`)    |
| Vector metrics   | 9598 | Prometheus metrics exporter          |
| VictoriaLogs     | 9428 | Log storage + LogsQL query API       |
| VictoriaMetrics  | 8428 | Metrics storage + PromQL query API   |
| Phoenix          | 6006 | Trace UI + OTLP HTTP (`/v1/traces`)  |
| Phoenix gRPC     | 4317 | OTLP gRPC collector                  |

All ports bind to `127.0.0.1` by default. Override with `AGENT_LOGS_BIND=0.0.0.0` in `.env`.

## Sending Logs

POST JSON to Vector. The URL path determines the `source` field.

```bash
# Backend logs (source=backend)
curl -X POST http://127.0.0.1:8688/ingest/logs \
  -H 'Content-Type: application/json' \
  -d '{"message":"server started","app":"myapp","service":"api","level":"info"}'

# Browser logs (source=browser)
curl -X POST http://127.0.0.1:8688/ingest/browser \
  -H 'Content-Type: application/json' \
  -d '{"message":"click","app":"myapp","screen_id":"checkout"}'

# Database logs (source=database)
curl -X POST http://127.0.0.1:8688/ingest/db \
  -H 'Content-Type: application/json' \
  -d '{"message":"slow query: 2.3s","app":"myapp","service":"postgres"}'

# Process logs (source=process)
curl -X POST http://127.0.0.1:8688/ingest/process \
  -H 'Content-Type: application/json' \
  -d '{"message":"process exited code=0","app":"myapp","service":"worker"}'
```

Vector automatically sets defaults for missing fields: `timestamp` (now), `level` (info), `message` ("no message"), `app` ("unknown"), `service` ("unknown").

## CLI Tools

### emit-log.sh

Send a single log event from the command line.

```bash
./scripts/emit-log.sh --app myapp "Server started on port 3000"
./scripts/emit-log.sh --app myapp --level error "Connection refused"
./scripts/emit-log.sh --app myapp --source browser --screen-id home "page loaded"
echo "piped message" | ./scripts/emit-log.sh --app myapp
```

### query-logs.sh

Query VictoriaLogs with LogsQL.

```bash
./scripts/query-logs.sh '{app="myapp"}'
./scripts/query-logs.sh --since 1h --limit 100 '{source="backend"} | level:error'
./scripts/query-logs.sh --pretty '{app="myapp"}'
./scripts/query-logs.sh --expect '{app="myapp"}'  # exit 0 if results, exit 1 if none
```

### tail-logs.sh

Live-tail streaming logs from VictoriaLogs.

```bash
./scripts/tail-logs.sh '{app="myapp"}'
./scripts/tail-logs.sh --timeout 60 '{level="error"}'
```

### tail-file.sh

Ship lines from a file or stdin to Vector with metadata enrichment.

```bash
./scripts/tail-file.sh --app myapp /var/log/myapp.log
some-command | ./scripts/tail-file.sh --app myapp --service worker
```

### query-metrics.sh

Query VictoriaMetrics with PromQL/MetricsQL.

```bash
./scripts/query-metrics.sh 'up'
./scripts/query-metrics.sh --expect 'up{job="vector"}'
./scripts/query-metrics.sh 'rate(http_requests_total[5m])'
```

### discover-app.sh

Detect project tooling, configs, and log files in a directory.

```bash
./scripts/discover-app.sh --dir /path/to/project
./scripts/discover-app.sh --pretty
```

Output is JSON: `{"package_managers":[], "vite_configs":[], "pm2_configs":[], "compose_files":[], "log_files":[]}`.

## Querying Logs

### With query-logs.sh

```bash
# All logs for an app
./scripts/query-logs.sh '{app="myapp"}'

# Filter by source and level
./scripts/query-logs.sh '{app="myapp",source="backend"} | level:error'

# Full-text search
./scripts/query-logs.sh '{app="myapp"} | "connection refused"'

# Time window
./scripts/query-logs.sh --since 1h '{app="myapp"}'

# Assert results exist (for CI/tests)
./scripts/query-logs.sh --expect '{app="myapp",source="backend"} | error'
```

### With raw curl

```bash
curl -s 'http://127.0.0.1:9428/select/logsql/query' \
  -d 'query={app="myapp",source="backend"} | limit 10'

# With time range
curl -s 'http://127.0.0.1:9428/select/logsql/query' \
  -d 'query={app="myapp"} | _time:15m | limit 50'

# Count by level
curl -s 'http://127.0.0.1:9428/select/logsql/query' \
  -d 'query={app="myapp"} | stats count(*) by (level)'
```

## Metrics

### With query-metrics.sh

```bash
# Check all scrape targets are up
./scripts/query-metrics.sh 'up'

# Vector event throughput
./scripts/query-metrics.sh 'rate(vector_component_sent_events_total[5m])'

# Assert a metric exists
./scripts/query-metrics.sh --expect 'up{job="vector"}'
```

### With raw curl

```bash
# Instant query
curl -s 'http://127.0.0.1:8428/api/v1/query?query=up'

# Range query
curl -s 'http://127.0.0.1:8428/api/v1/query_range' \
  --data-urlencode 'query=rate(vector_component_sent_events_total[5m])' \
  -d 'start=-1h&step=60s'
```

## Log Schema

### Required fields

Vector sets defaults if missing. Always include `app` for meaningful filtering.

| Field       | Type   | Default     | Description                         |
|-------------|--------|-------------|-------------------------------------|
| `timestamp` | string | now (ISO)   | Event time in RFC3339 format        |
| `level`     | string | `"info"`    | debug, info, warn, error, fatal     |
| `message`   | string | `"no message"` | Human-readable log message      |
| `source`    | string | from path   | backend, browser, database, process |
| `app`       | string | `"unknown"` | Application name                    |
| `service`   | string | `"unknown"` | Service/component within app        |

### Recommended fields

| Field        | Description                        |
|--------------|------------------------------------|
| `agent_id`   | Agent identifier                   |
| `run_id`     | Session/run identifier             |
| `worktree`   | Git branch or worktree path        |
| `screen_id`  | Browser screen/route identifier    |
| `pid`        | Process ID                         |
| `hostname`   | Machine hostname                   |
| `log_file`   | Source file path (for tail-file)   |
| `error_stack`| Error stack trace                  |
| `route`      | HTTP route or page path            |
| `url`        | Full URL (browser)                 |
| `user_agent` | Browser user agent string          |
| `viewport`   | Viewport dimensions (browser)      |

Do not add high-cardinality fields (`agent_id`, `run_id`, `screen_id`) to VictoriaLogs `_stream_fields`. They are indexed as log fields, not stream labels.

## Environment Variables

| Variable              | Default                      | Used by            |
|-----------------------|------------------------------|--------------------|
| `AGENT_LOGS_URL`      | `http://127.0.0.1:8688`     | All scripts, packages |
| `VICTORIA_LOGS_URL`   | `http://127.0.0.1:9428`     | query-logs, tail-logs |
| `VICTORIA_METRICS_URL`| `http://127.0.0.1:8428`     | query-metrics      |
| `AGENT_ID`            | hostname                     | emit-log, tail-file |
| `RUN_ID`              | `<timestamp>-<pid>`          | emit-log, tail-file |
| `WORKTREE`            | git branch or cwd basename   | emit-log, tail-file |
| `APP`                 | (none)                       | node-logger        |
| `SERVICE`             | (none)                       | node-logger        |

## Integration Packages

### @agent-logs/browser-logger

Captures browser `console.*`, unhandled errors, and promise rejections.

```typescript
import { createLogger } from "@agent-logs/browser-logger";

const logger = createLogger({
  app: "myapp",
  screenId: "dashboard",
});

logger.info("Page loaded");
logger.error("Something failed", { context: "checkout" });

// Remove global error listeners
logger.destroy();
```

Posts to `/__agent_logs/browser` by default (use Vite plugin proxy in dev).

### @agent-logs/node-logger

Wraps `console.*` to emit logs to Vector while preserving normal console output.

```typescript
import { createLogger } from "@agent-logs/node-logger";

const logger = createLogger({
  app: "myapp",
  service: "api",
});

logger.info("Server started on port 3000");
logger.error("Database connection failed");
```

Posts to `http://127.0.0.1:8688/ingest/logs`. Override with `url` option or `AGENT_LOGS_URL` env var.

### @agent-logs/vite-plugin

Vite plugin that proxies `/__agent_logs/browser` to Vector and optionally injects browser-logger.

```typescript
// vite.config.ts
import agentLogs from "@agent-logs/vite-plugin";

export default {
  plugins: [
    agentLogs({ app: "myapp", inject: true }),
  ],
};
```

## Vite Proxy

The Vite plugin sets up a dev server proxy:

```
Browser: POST /__agent_logs/browser
  --> Vite dev server proxy
  --> http://127.0.0.1:8688/ingest/browser (Vector)
```

Configuration options:

| Option   | Default                      | Description                            |
|----------|------------------------------|----------------------------------------|
| `target` | `AGENT_LOGS_URL` or `:8688`  | Vector ingest base URL                 |
| `app`    | `"app"`                      | App name for injected logger           |
| `inject` | `false`                      | Auto-inject browser-logger script tag  |

When `inject: true`, a `<script type="module">` tag is added to HTML in dev mode that initializes browser-logger with the configured `app` name.

## Lifecycle

```bash
./start.sh              # Preflight checks + docker compose up -d --wait
./scripts/up.sh         # docker compose up -d (no preflight)
./scripts/down.sh       # docker compose down (preserves volumes)
./scripts/reset.sh      # docker compose down -v (wipes all data)
```

## Testing

Run the end-to-end test suite (requires the stack to be running):

```bash
./scripts/e2e.sh
```

The e2e script:
1. Starts the stack if not already running
2. Emits test logs via each ingest path
3. Queries VictoriaLogs to verify ingestion
4. Checks metrics are being scraped
5. Reports pass/fail for each check

## Troubleshooting

**Stack fails to start**
- Check Docker is running: `docker info`
- Check ports are free: `lsof -i :8688 -i :9428 -i :8428 -i :6006`
- Copy env file if missing: `cp .env.example .env`

**Logs not appearing in queries**
- Verify Vector is healthy: `curl -s http://127.0.0.1:8686/health`
- Check VictoriaLogs health: `curl -s http://127.0.0.1:9428/health`
- Ensure `app` field is set (logs with `app="unknown"` are still stored but hard to filter)
- Wait 1-2 seconds after ingest for indexing

**curl to Vector returns connection refused**
- Stack not running: `./start.sh`
- Port mismatch: check `.env` for `VECTOR_INGEST_PORT`

**VictoriaLogs health check fails in container**
- Known issue: use `127.0.0.1` not `localhost` (IPv6 resolution fails in alpine containers)

**Metrics query returns empty results**
- vmagent scrapes every 15s by default; wait and retry
- Check scrape targets: `curl -s http://127.0.0.1:8428/api/v1/query?query=up`

**Phoenix traces not showing**
- Verify OTLP endpoint: `curl -s http://127.0.0.1:6006/healthz`
- Send test trace via gRPC (4317) or HTTP (6006/v1/traces)

**Vector VRL transform errors**
- VRL is strict about error handling; use `if !exists(.field)` patterns
- Check Vector logs: `docker compose logs vector`

**Disk buffer full**
- Vector buffers to disk (512MB max). If VictoriaLogs is down too long, Vector blocks.
- Fix: restart VictoriaLogs, then Vector will flush. Or `./scripts/reset.sh` to wipe everything.
