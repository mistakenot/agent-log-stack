# Agent Logs

Local observability stack for AI coding agents. Collects logs, metrics, and traces from apps and runtimes the agent is driving.

## Quick Start

```bash
git clone <repo-url> && cd agent-logs
./start.sh
# Stack is ready. OTLP on :4318, query on :9428, metrics on :8428, traces UI on :6006.
```

## Architecture

```
                         +-------------------+
                         |   Your App/Agent  |
                         +-------------------+
                                  |
                    OTLP JSON (HTTP :4318 / gRPC :4317)
                                  v
                      +-----------------------+
                      | Vector (OTLP Collector)|
                      | opentelemetry source  |
                      | + VRL normalize       |
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

                      +-----------------------+
                      | Phoenix (6006)        |
                      | Trace UI              |
                      +-----------------------+
```

## Port Reference

| Service          | Port | Purpose                              |
|------------------|------|--------------------------------------|
| Vector OTLP HTTP | 4318 | OTLP HTTP ingest (`/v1/logs`, `/v1/traces`) |
| Vector OTLP gRPC | 4317 | OTLP gRPC ingest                     |
| Vector metrics   | 9598 | Prometheus metrics exporter           |
| VictoriaLogs     | 9428 | Log storage + LogsQL query API       |
| VictoriaMetrics  | 8428 | Metrics storage + PromQL query API   |
| Phoenix          | 6006 | Trace UI                             |

All ports bind to `127.0.0.1` by default. Override with `AGENT_LOGS_BIND=0.0.0.0` in `.env`.

## Sending Logs

### With emit-log.sh (simplest)

```bash
./scripts/emit-log.sh --app myapp "Server started on port 3000"
./scripts/emit-log.sh --app myapp --level error "Connection refused"
./scripts/emit-log.sh --app myapp --source browser --screen-id home "page loaded"
echo "piped message" | ./scripts/emit-log.sh --app myapp
```

### With OTLP JSON (curl)

POST OTLP JSON to the collector at `http://127.0.0.1:4318/v1/logs`:

```bash
curl -X POST http://127.0.0.1:4318/v1/logs \
  -H 'Content-Type: application/json' \
  -d '{
    "resourceLogs": [{
      "resource": {
        "attributes": [
          {"key": "service.name", "value": {"stringValue": "api"}},
          {"key": "app", "value": {"stringValue": "myapp"}}
        ]
      },
      "scopeLogs": [{
        "scope": {},
        "logRecords": [{
          "timeUnixNano": "1700000000000000000",
          "severityText": "INFO",
          "severityNumber": 9,
          "body": {"stringValue": "server started"},
          "attributes": [
            {"key": "source", "value": {"stringValue": "backend"}}
          ]
        }]
      }]
    }]
  }'
```

### With OpenTelemetry SDKs

Any OTLP-compatible SDK can send logs. Set the endpoint:

```bash
export OTEL_EXPORTER_OTLP_ENDPOINT=http://127.0.0.1:4318
```

**Node.js** (`@opentelemetry/sdk-logs`):

```javascript
const { LoggerProvider, SimpleLogRecordProcessor } = require('@opentelemetry/sdk-logs');
const { OTLPLogExporter } = require('@opentelemetry/exporter-logs-otlp-http');

const provider = new LoggerProvider();
provider.addLogRecordProcessor(new SimpleLogRecordProcessor(
  new OTLPLogExporter({ url: 'http://127.0.0.1:4318/v1/logs' })
));
const logger = provider.getLogger('myapp');
logger.emit({ body: 'hello from node', severityText: 'INFO' });
```

**Python** (`opentelemetry-sdk`, `opentelemetry-exporter-otlp-proto-http`):

```python
from opentelemetry.sdk._logs import LoggerProvider
from opentelemetry.sdk._logs.export import SimpleLogRecordProcessor
from opentelemetry.exporter.otlp.proto.http._log_exporter import OTLPLogExporter

provider = LoggerProvider()
provider.add_log_record_processor(
    SimpleLogRecordProcessor(OTLPLogExporter())
)
logger = provider.get_logger("myapp")
```

**Browser**: Use `@opentelemetry/sdk-logs` with `@opentelemetry/exporter-logs-otlp-http`, pointed at your dev server proxy or directly at `http://127.0.0.1:4318`.

Vector normalizes OTLP fields via VRL: `body` becomes `message`, `severityText` becomes `level`, resource attributes `app` and `service.name` become top-level fields.

#### OTLP severity mapping

| Level | severityText | severityNumber |
|-------|-------------|----------------|
| trace | TRACE       | 1              |
| debug | DEBUG       | 5              |
| info  | INFO        | 9              |
| warn  | WARN        | 13             |
| error | ERROR       | 17             |
| fatal | FATAL       | 21             |

#### timeUnixNano

- Bash: `"$(date +%s)000000000"`
- JavaScript: `String(Date.now() * 1000000)`

## CLI Tools

### emit-log.sh

Send a single log event via OTLP.

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

Ship lines from a file or stdin to the OTLP collector with metadata enrichment.

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

Vector normalizes OTLP fields to these names. Always include `app` for meaningful filtering.

| Field       | OTLP source              | Default        | Description                         |
|-------------|--------------------------|----------------|-------------------------------------|
| `message`   | `body.stringValue`       | `"no message"` | Human-readable log message          |
| `level`     | `severityText`           | `"info"`        | debug, info, warn, error, fatal     |
| `app`       | resource attr `app`      | `"unknown"`     | Application name                    |
| `service`   | resource attr `service.name` | `"unknown"` | Service/component within app        |
| `source`    | log attr `source`        | `"backend"`     | backend, browser, database, process |

### Recommended fields (log attributes)

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

Do not add high-cardinality fields (`agent_id`, `run_id`, `screen_id`) to VictoriaLogs `_stream_fields`. They are indexed as log fields, not stream labels.

## Environment Variables

| Variable                       | Default                      | Used by            |
|--------------------------------|------------------------------|--------------------|
| `AGENT_LOGS_URL`               | `http://127.0.0.1:4318`     | emit-log, tail-file, log-generator |
| `OTEL_EXPORTER_OTLP_ENDPOINT`  | (none)                       | OpenTelemetry SDKs |
| `VICTORIA_LOGS_URL`            | `http://127.0.0.1:9428`     | query-logs         |
| `VICTORIA_METRICS_URL`         | `http://127.0.0.1:8428`     | query-metrics      |
| `AGENT_ID`                     | hostname                     | emit-log, tail-file |
| `RUN_ID`                       | `<timestamp>-<pid>`          | emit-log, tail-file |
| `WORKTREE`                     | git branch or cwd basename   | emit-log, tail-file |

## Lifecycle

```bash
./start.sh              # Preflight checks + docker compose up -d --wait
./scripts/up.sh         # docker compose up -d (no preflight)
./scripts/down.sh       # docker compose down (preserves volumes)
./scripts/reset.sh      # docker compose down -v (wipes all data)
```

## Testing

```bash
./scripts/e2e.sh
```

The e2e script starts an isolated stack, emits OTLP test logs, queries VictoriaLogs to verify ingestion, checks metrics, and reports pass/fail.

## Troubleshooting

**Stack fails to start**
- Check Docker is running: `docker info`
- Check ports are free: `lsof -i :4318 -i :9428 -i :8428 -i :6006`
- Copy env file if missing: `cp .env.example .env`

**Logs not appearing in queries**
- Verify Vector is healthy: `curl -s http://127.0.0.1:8686/health` (Vector internal API, not exposed to host by default)
- Check VictoriaLogs health: `curl -s http://127.0.0.1:9428/health`
- Ensure `app` resource attribute is set
- Wait 1-2 seconds after ingest for indexing

**OTLP ingest returns connection refused**
- Stack not running: `./start.sh`
- Port mismatch: check `.env` for `OTEL_HTTP_PORT`

**VictoriaLogs health check fails in container**
- Known issue: use `127.0.0.1` not `localhost` (IPv6 resolution fails in alpine containers)

**Metrics query returns empty results**
- vmagent scrapes every 15s by default; wait and retry
- Check scrape targets: `curl -s http://127.0.0.1:8428/api/v1/query?query=up`

**Vector VRL transform errors**
- VRL is strict about error handling; use `if !exists(.field)` patterns
- Check Vector logs: `docker compose logs vector`

**Disk buffer full**
- Vector buffers to disk (512MB max). If VictoriaLogs is down too long, Vector blocks.
- Fix: restart VictoriaLogs, then Vector will flush. Or `./scripts/reset.sh` to wipe everything.
