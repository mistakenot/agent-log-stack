# Agent Dev Observability Requirements

## Purpose

Create a self-contained local observability repository for development environments driven by AI coding agents running in parallel on the same machine. The stack must make logs and basic metrics from development servers, browser sessions, databases, local services, and test workloads easy for agents to collect, enrich, query, and use as feedback while they work.

The design is inspired by agent-first harness engineering: agents become more useful when application logs, metrics, and runtime state are directly legible through local tools and query APIs. This repository should provide that capability without introducing a heavyweight platform.

The default user is always an agent, not a human operator. Human-readable affordances are useful for debugging, but the primary product surface is CLI tools and HTTP endpoints that agents can call, parse, and loop on.

This repository is not primarily for collecting the coding agent's own chat transcript or internal tool-call history. It is for collecting the observable behavior of the app and local runtime that the agent is modifying and driving.

## Product Principles

- Simple first: the install path must be clone, run `./start.sh`, done.
- Local and trusted: no authentication, no TLS, no multi-user authorization model.
- Agent-aware: the schema supports metadata to separate parallel agents, worktrees, apps, screens, and test runs when provided. Auto-derived defaults fill in when env vars are unset.
- Lightweight: prefer single-node VictoriaLogs, Vector, and small helper scripts over clusters or managed services.
- Queryable by agents: all important data must be accessible over documented HTTP APIs and scriptable CLI wrappers with machine-readable output.
- Agent-first UX: optimize for shell commands, stable exit codes, JSON/NDJSON responses, and concise diagnostics over dashboards.
- Disposable by default: the stack should be easy to reset between experiments while still supporting a persistent data volume for longer local sessions.
- Deterministic tests: E2E tests must stand up the stack, generate logs, and prove the logs are queryable through VictoriaLogs.

## Harness Engineering Alignment

The OpenAI harness engineering pattern treats observability as part of the agent's working environment, not as a separate human operations layer. This repository should implement the same principle at local-development scale:

- Application legibility is the goal: logs and metrics must be directly visible to agents while they are coding, testing, and validating changes.
- Feedback loops matter more than dashboards: agents should be able to emit a workload, query the resulting logs/metrics, change code or configuration, restart, and query again.
- Worktree context is first-class: every event must make it possible to distinguish one worktree, task, run, and agent from another.
- Ephemeral stacks should be easy: tests and future per-worktree workflows must be able to create an isolated stack and tear it down after the task.
- Repository-local knowledge is the system of record: commands, schemas, examples, and query recipes must live in this repo, not in external notes.
- Mechanical enforcement beats prose: the repo should eventually include tests or lint checks that validate required log fields, query script behavior, and E2E coverage.
- Keep the stack boring and inspectable: agents should be able to understand the Compose file, Vector config, scripts, and schemas without relying on hidden services.

## Startup Contract

The repository must be designed to work on a target machine with the smallest possible workflow:

```sh
git clone <repo-url>
cd <repo>
./start.sh
```

After `./start.sh` completes:

- VictoriaLogs is accepting logs and answering query API requests.
- Vector is accepting browser, process, app, and database log ingest.
- VictoriaMetrics and vmagent are running for basic stack metrics.
- Phoenix is running for local trace inspection.
- The script prints the local URLs and one copy-paste query command.
- The script exits non-zero with concise diagnostics if Docker, Compose, ports, or required files are unavailable.

`./start.sh` may call lower-level scripts such as `scripts/up.sh`, but agents should not need to know those scripts for first use.

## Non-Goals

- Authentication, authorization, TLS, user management, SSO, or secret management.
- Production multi-tenant isolation.
- Kubernetes, Helm, or cloud deployment.
- Alerting, paging, dashboards, or long-term retention as MVP requirements.
- Human-first dashboard workflows. The VictoriaLogs Web UI may be exposed for manual debugging, but it is not the main interface.
- A full production tracing platform. A basic local Phoenix instance is in scope; deeper trace retention and eval workflows are out of the MVP.
- Building a custom query language or custom log database.
- Capturing coding-agent internal conversations, prompts, or tool-call transcripts as the core data source.
- MCP tools or skills for log querying (post-MVP consideration).

## Primary Use Cases

1. An agent starts a task in a worktree, runs the app/dev server/database, and queries only logs for that worktree, app, run, and browser screen.
2. Multiple agents run different worktrees or app instances on the same host and can collect runtime logs into the same stack without mixing contexts.
3. A frontend app posts browser console/errors to a same-origin endpoint. During local development, Vite proxies that endpoint to the local logging stack.
4. A test script stands up the stack, runs a scratch app/log generator, emits backend, dev-server, database, and browser-style logs, and verifies them through the VictoriaLogs LogsQL HTTP API.
5. Agents inspect stack health through CLI-accessible lightweight metrics and use failures as feedback for retries or fixes.
6. Optional LLM/application traces from Claude Code, Codex, MCP servers, or app-level OpenInference/OpenTelemetry instrumentation are sent to local Phoenix for trace inspection.

## Prior Session Observations

Local `autosearch` history shows that coding-agent work is heavily CLI-driven and often involves long-running application processes. The stack should account for the runtime signals agents repeatedly need to inspect:

- Agents frequently inspect `go test`, `go build`, `uv run`, `npm run dev`, Vite, PM2, GitHub CLI, and Docker-style command output.
- Web-app sessions commonly run Vite dev or preview servers under PM2 and inspect `.pm2/logs/*-out.log` and `*-error.log`.
- Agents often use `tail -F ... | grep -E "error|Error|Exception|Traceback|FAILED"` as an improvised observability loop.
- Browser debugging works best when console and page errors are available through CLI tools rather than manual DevTools.
- Parallel subagents are common, so driver metadata must be represented explicitly enough to filter app/runtime logs by parent session, subagent, run, and workspace when the app is being driven by agents.

These observations push the MVP toward default capture paths and command-oriented query helpers instead of requiring each application to adopt a custom logging framework.

## Low-Configuration Integration Requirements

The stack should "just work" with typical local web applications and codebases. Explicit instrumentation should improve log quality, but useful logs must be captured even when the application only has normal console output or a Vite dev server.

Required integration modes:

- HTTP JSON ingest for explicit application logs.
- Drop-in Vite proxy integration for browser logs.
- Browser logger helper that auto-captures `console.log`, `console.warn`, `console.error`, `window.onerror`, and `unhandledrejection` when enabled.
- Node logger helper that can wrap `console.*` and emit process metadata without forcing the app to replace its logger.
- File-tail ingestion for common local process logs, especially PM2 logs such as `~/.pm2/logs/*.log`.
- Optional Docker container stdout ingestion for apps launched under the same Compose project.
- Database log ingestion for local databases when exposed as Docker stdout, known log files, or explicit app-level database diagnostics.

Configuration should be minimal:

- Defaults must work with `AGENT_LOGS_URL=http://127.0.0.1:8688`.
- Agents should be able to set `AGENT_ID`, `RUN_ID`, `WORKTREE`, `APP`, and `SERVICE` once in the environment. These values identify the driver context, not necessarily the process that produced the log.
- If those env vars are missing, helper scripts should derive safe defaults from cwd, git branch, hostname, pid, and timestamp.
- Integration packages should accept overrides, but examples must show the shortest path first.

Recommended integration artifacts:

- `packages/browser-logger`: small browser helper for frontend apps.
- `packages/node-logger`: small Node helper for CLIs, servers, scripts, and test harnesses.
- `packages/vite-plugin-agent-logs`: Vite plugin that configures the proxy and optionally injects the browser logger in dev mode.
- `scripts/discover-app.sh`: optional helper that reports detected package manager, Vite config, PM2 config, Docker Compose files, and likely log files.
- `scripts/tail-file.sh`: optional helper for sending any local log file or command output into Vector with metadata.

Non-requirements for integration:

- Apps must not need to migrate to a specific logging framework.
- Apps must not need to run inside this repository.
- Frontend apps must not need CORS changes when using the Vite proxy path.
- Codebases must not need to change more than one Vite config line for browser logging.

## Architecture

### MVP Components

- `victoria-logs`: single-node VictoriaLogs for log storage and querying.
- `vector`: local collector and sidecar-style HTTP ingest service.
- `victoria-metrics`: single-node VictoriaMetrics for Prometheus-style metrics.
- `vmagent`: scrapes Prometheus-compatible endpoints and writes to VictoriaMetrics.
- `phoenix`: local Arize Phoenix instance for LLM/application trace inspection.
- `packages/browser-logger`: drop-in browser logging helper.
- `packages/node-logger`: drop-in Node logging helper.
- `packages/vite-plugin-agent-logs`: Vite proxy/logger integration.
- `examples/log-generator`: tiny scratch app or script used by E2E tests to generate deterministic logs and metrics.
- `examples/vite-browser-logs`: tiny Vite app used by E2E tests to prove browser logs can flow through a Vite proxy.
- `scripts/e2e.sh`: end-to-end test runner.
- `scripts/query-logs.sh`: thin wrapper around VictoriaLogs query API for agent use.
- `scripts/tail-logs.sh`: optional live-tail wrapper around VictoriaLogs tail API.
- `scripts/emit-log.sh`: optional small CLI for agents that need a stable log-emission command instead of hand-written `curl`.
- `scripts/tail-file.sh`: optional file or stdin shipper for PM2/dev-server logs.
- `scripts/up.sh` and `scripts/down.sh`: convenience wrappers around Docker Compose.

### Data Flow

Backend, dev-server, database, and service logs:

```text
app, dev server, database, or local service -> HTTP/file/stdout ingest on Vector -> Vector normalization -> VictoriaLogs /insert/jsonline -> LogsQL query API
```

Frontend browser logs:

```text
browser logger -> POST /__agent_logs/browser -> Vite proxy -> Vector /ingest/browser -> Vector normalization -> VictoriaLogs /insert/jsonline
```

Existing process logs:

```text
PM2 log file, Docker stdout, database log, or command output -> tail helper or Vector file source -> Vector normalization -> VictoriaLogs /insert/jsonline
```

LLM/application traces:

```text
Claude Code, Codex harness, MCP server, or instrumented app -> OTLP -> Phoenix
```

Metrics:

```text
VictoriaLogs /metrics
Vector Prometheus exporter /metrics
sample app /metrics
frontend log path counters, if exposed
    -> vmagent scrape
    -> VictoriaMetrics /api/v1/write
    -> VictoriaMetrics query API
```

### Why Vector Is The Ingest Sidecar

Vector's HTTP server source is stable, stateless, and fits the sidecar/aggregator role for logs and lightweight event ingestion. Vector's HTTP sink can send newline-delimited JSON to VictoriaLogs. This keeps browser and backend log ingestion simple while still allowing normalization, default fields, batching, buffering, retries, and metadata enrichment in one place.

## Repository Layout

The implementation should create this shape:

```text
.
├── README.md
├── requirements.md
├── docker-compose.yml
├── .env.example
├── start.sh
├── config/
│   ├── vector.yaml
│   └── vmagent.yaml

<!-- RESOLVED(P3): config/victoria-logs.env listed but undefined and unused
REVIEW: This file appears in the repository layout but no section in the requirements describes its contents or purpose. The current implementation configures VictoriaLogs entirely through CLI args in docker-compose.yml.
AUTHOR: Removed from layout. VictoriaLogs is configured via docker-compose.yml command args and .env.example variables, which is simpler and consistent with how the other services are configured.
-->
├── packages/
│   ├── browser-logger/
│   ├── node-logger/
│   └── vite-plugin-agent-logs/
├── scripts/
│   ├── up.sh
│   ├── down.sh
│   ├── reset.sh
│   ├── emit-log.sh
│   ├── tail-file.sh
│   ├── query-logs.sh
│   ├── tail-logs.sh
│   ├── query-metrics.sh
│   ├── discover-app.sh
│   └── e2e.sh
├── examples/
│   ├── log-generator/
│   └── vite-browser-logs/
└── tests/
    └── e2e/
```

## Docker Compose Requirements

- The default command must be `docker compose up -d`.
- All published ports must bind to `127.0.0.1` by default.
- Host binding must be configurable with an env var such as `AGENT_LOGS_BIND=0.0.0.0`.
- Images must be pinned through `.env.example`; committed Compose files must not use unpinned `latest`.
- Volumes:
  - `victoria_logs_data` for VictoriaLogs.
  - `victoria_metrics_data` for VictoriaMetrics.
  - `vector_data` for Vector disk buffers.
  - `phoenix_data` for Phoenix SQLite working data.
- Health checks must wait for HTTP endpoints before tests run.
- `docker compose down -v` must fully reset the stack.
- The stack must expose:
  - VictoriaLogs HTTP API on host port `9428`.
  - VictoriaLogs Web UI at `/select/vmui/`.
  - Vector ingest HTTP endpoint on a configurable host port, for example `8688`.
  - Vector metrics exporter endpoint, for example `9598`.
  - VictoriaMetrics HTTP API on host port `8428`.
  - Phoenix UI and OTLP HTTP collector on host port `6006`.
  - Phoenix OTLP gRPC collector on host port `4317`.

## VictoriaLogs Requirements

- Run single-node VictoriaLogs.
- Store logs at `/victoria-logs-data` in the container.
- Use the JSON line stream API endpoint `/insert/jsonline`.
- Use `/select/logsql/query` for E2E verification and agent query scripts.
- Use `/select/logsql/tail` as a documented optional live-tail path.
- Expose the built-in Web UI at `/select/vmui/` only as a secondary manual-debugging surface.
- All required workflows must work through CLI tools and HTTP APIs without opening the Web UI.
- Default retention should be short and local-development friendly, for example 7 days, configurable by env. Both VictoriaLogs and VictoriaMetrics retention must be configurable through `.env` variables (`VICTORIA_LOGS_RETENTION` and `VICTORIA_METRICS_RETENTION`).

<!-- RESOLVED(P2): VictoriaMetrics retention is not env-configurable despite the same pattern being established for VictoriaLogs
REVIEW: docker-compose.yml hardcodes VictoriaMetrics retention as `-retentionPeriod=7d` without an env var, while VictoriaLogs uses `${VICTORIA_LOGS_RETENTION:-7d}`.
AUTHOR: Updated requirement to explicitly name both env vars. Implementation should add `VICTORIA_METRICS_RETENTION` to `.env.example` and use `${VICTORIA_METRICS_RETENTION:-7d}` in docker-compose.yml.
-->
- Query concurrency and duration should be configured conservatively, for example:
  - maximum query duration: 10s to 30s by default.
  - maximum concurrent query requests: enough for several parallel agents, configurable.

## Vector Ingest Requirements

### HTTP Sources

Vector must expose at least these endpoints:

- `POST /ingest/logs`: backend, dev-server, local service, CLI workload, and scratch app logs.
- `POST /ingest/browser`: frontend browser logs proxied from Vite.
- `POST /ingest/process`: logs captured from PM2, command output, file tailing, or Docker stdout.
- `POST /ingest/db`: database logs and database diagnostic events.

<!-- RESOLVED(P2): /ingest/metrics endpoint purpose and routing are ambiguous
REVIEW: The `/ingest/metrics` endpoint mixed concerns — this is a log ingestion pipeline to VictoriaLogs, not a metrics write path.
AUTHOR: Removed `/ingest/metrics`. Metrics flow exclusively through Prometheus scrape via vmagent. Log-shaped metric events (e.g. "latency was 250ms") belong in `/ingest/logs` with appropriate fields. Time-series metrics belong in VictoriaMetrics via the Prometheus exposition format.
-->
- `GET /health`: simple health endpoint if Vector config supports it directly; otherwise provide script-level health checks against the Vector API or metrics exporter.

The log endpoints must accept `application/json` single-event payloads. They should also accept newline-delimited JSON when practical because VictoriaLogs and Vector both fit NDJSON workflows well.

### Normalization

Vector transforms must normalize every log event into a flat JSON object before sending it to VictoriaLogs.

Required output fields:

- `timestamp`: RFC3339 timestamp. If absent, set to ingestion time.
- `level`: `trace`, `debug`, `info`, `warn`, `error`, or `fatal`. If absent, set `info`.
- `message`: human-readable log message. If absent, derive from `msg`, `_msg`, `event`, or serialize the payload.
- `source`: emitting source category. Vector auto-derives a default from the ingest path (`/ingest/browser` → `browser`, `/ingest/db` → `database`, `/ingest/process` → `process`, all others → `backend`). Clients may override by setting `source` explicitly in the JSON payload. Recognized values: `backend`, `browser`, `dev_server`, `database`, `worker`, `queue`, `cache`, `test`, `tool`, `process`, `infra`, or `unknown`. Path-based defaults are a convenience; explicit `source` in the payload always takes precedence.

<!-- RESOLVED(P2): Most source values cannot be auto-derived — only 4 paths are routed
REVIEW: 13 source values listed but only 4 auto-derived from path. `frontend` vs `browser` distinction was unclear.
AUTHOR: Rewrote to clarify that path routing is a convenience default and explicit `source` in the payload takes precedence. Removed `frontend` — browser-side logs are `browser`, server-side rendering logs are `backend` with `service` distinguishing the component. This matches how agents actually think about the distinction.
-->

- `app`: application or repo-local app name.
- `service`: service/component name.
Recommended output fields:

- `agent_id`: stable identifier for the agent or harness driving the app/runtime. This is query context, not the log producer. Auto-derived from env or hostname when absent.
- `run_id`: caller-defined scope (task, test run, session — the caller decides). Auto-derived from timestamp and pid when absent.
- `worktree`: worktree path or short worktree name. Auto-derived from cwd or git branch when absent.
- `screen_id`: logical UI screen identifier, supplied by the frontend app (not route-derived).
- `session_id`
- `task_id`
- `thread_id`
- `repo`
- `branch`
- `commit_sha`
- `pid`
- `hostname`
- `container_name`
- `process_name`
- `process_type`
- `log_file`
- `db_system`
- `db_name`
- `route`
- `url`
- `pathname`
- `component`
- `event_name`
- `request_id`
- `trace_id`
- `span_id`
- `duration_ms`
- `status_code`
- `error_name`
- `error_stack`
- `user_journey`
- `browser`
- `viewport`
- `model`: LLM model identifier when relevant.
- `agent_tool`: agent tooling identifier (e.g. `claude-code`, `codex`).
- `approval_mode`: agent approval/autonomy mode when relevant.

### Metadata Sources

Clients provide metadata through JSON payload fields. This is the primary and MVP-supported path. Agents constructing `curl` commands or using helper scripts naturally include metadata as JSON fields, which aligns with the agent-first design.

Future consideration: HTTP headers (`X-Agent-Id`, `X-Run-Id`, `X-Worktree`, `X-App`, `X-Screen-Id`) and query string fields could provide metadata for clients that cannot easily modify the JSON body (e.g. third-party log shippers). This requires Vector's `headers_key` config option and a VRL merge step to apply header values only when the corresponding JSON field is absent. This is not required for the MVP.

<!-- RESOLVED(P2): Vector http_server source does not natively expose request headers as event fields
REVIEW: The original precedence chain (JSON > headers > query > defaults) required Vector header extraction that doesn't exist in the current config.
AUTHOR: Simplified to JSON-payload-only for MVP. Agents set metadata in JSON bodies — that's the natural agent-first path. Header/query extraction noted as a future enhancement with the specific Vector config approach (`headers_key`) for when third-party shippers need it.
-->

### VictoriaLogs Sink

Vector must send logs to:

```text
http://victoria-logs:9428/insert/jsonline?_stream_fields=app,source,service&_msg_field=message&_time_field=timestamp
```

<!-- RESOLVED(P1): Stream fields in sink URL contradict Implementation Notes
REVIEW: Original URL had `_stream_fields=app,source,worktree,service,process_type` but Implementation Notes said to keep high-cardinality fields out of stream fields.
AUTHOR: Fixed sink URL to `_stream_fields=app,source,service` — matching the Implementation Notes and current implementation. `worktree` is per-agent/per-task and can be high-cardinality. `process_type` is only bounded if the emitting app uses a fixed set. Both remain queryable as normal fields, just not stream fields.
-->

Notes:

- `agent_id` and `run_id` should remain normal queryable fields by default. They are often high-cardinality driver context, not stable producer identity.
- `screen_id` should remain a normal queryable field by default, not a stream field, unless testing shows it has bounded cardinality.
- Use gzip compression for the sink.
- Use JSON encoding.
- Use newline-delimited framing.
- Disable startup health check for the sink if VictoriaLogs does not support the exact health probe Vector expects.
- Use a disk buffer for the VictoriaLogs sink so short VictoriaLogs restarts do not drop logs.
- Use backpressure instead of dropping newest events by default.

## Log Schema Contract

### Event Example

```json
{
  "timestamp": "2026-06-07T12:00:00Z",
  "level": "info",
  "message": "checkout screen rendered",
  "source": "frontend",
  "app": "scratch-vite",
  "service": "web",
  "agent_id": "codex-a",
  "run_id": "run-20260607-120000-a",
  "worktree": "feature-checkout",
  "screen_id": "checkout",
  "route": "/checkout",
  "component": "CheckoutPage",
  "event_name": "screen_rendered"
}
```

### Query Examples

Query scripts must default to output that an agent can parse. JSON or NDJSON is preferred. Human pretty-printing should be behind an explicit flag such as `--pretty`.

Agent-scoped logs:

```sh
curl -s http://127.0.0.1:9428/select/logsql/query \
  -d 'query={app="scratch",source="backend"} AND agent_id:codex-a AND run_id:run-123 | limit 50'
```

Screen-scoped frontend logs:

```sh
curl -s http://127.0.0.1:9428/select/logsql/query \
  -d 'query={app="scratch-vite",source="browser"} AND agent_id:codex-a AND run_id:run-123 AND screen_id:checkout | limit 50'
```

E2E marker:

```sh
curl -s http://127.0.0.1:9428/select/logsql/query \
  -d 'query={app="agent-dev-observability-e2e"} AND run_id:RUN_ID AND "e2e_marker" | limit 10'
```

## Frontend Browser Logging Requirements

### Browser Client

The repository must include a tiny browser logging helper or example that:

- Provides `log.info`, `log.warn`, and `log.error` functions.
- Posts to `/__agent_logs/browser`.
- Sends one JSON event or a small batch of JSON events.
- Includes `screen_id`, `route`, `url`, `user_agent`, and viewport metadata.
- Captures unhandled errors and unhandled promise rejections in the example app.
- Does not require auth headers or CORS because Vite provides same-origin proxying.
- Avoids logging secrets by documenting that callers must not include tokens, passwords, cookies, API keys, or source files containing secrets.
- Accepts malformed payloads with best-effort normalization rather than rejecting them. Missing fields get defaults (same as backend log normalization).

### Vite Proxy

The example Vite app must include a proxy like:

```ts
server: {
  proxy: {
    "/__agent_logs/browser": {
      target: "http://127.0.0.1:8688",
      changeOrigin: true,
      rewrite: (path) => path.replace(/^\/__agent_logs\/browser$/, "/ingest/browser")
    }
  }
}
```

The E2E test must prove this path works by starting the Vite example, causing browser-style logs to be posted through the proxy, and querying them from VictoriaLogs.

## Runtime Log Capture Requirements

### Development Servers

The stack must make common local development-server logs easy to capture without app code changes.

- Capture PM2 logs from known paths such as `~/.pm2/logs/*-out.log` and `~/.pm2/logs/*-error.log`.
- Capture command stdout/stderr through `scripts/tail-file.sh` or a companion `scripts/run-with-logs.sh` helper.
- Capture Docker Compose service stdout/stderr when apps are launched under Docker.
- Normalize development-server logs with `source="dev_server"` or `source="process"`.
- Include `process_name`, `process_type`, `pid`, `log_file`, `app`, `service`, `worktree`, `agent_id`, and `run_id` when known.
- Provide examples for Vite dev server, Vite preview, generic Node server, and a long-running test watcher.

### Agent-Driven Browser Sessions

Browser logs are a primary signal because agents often validate UI behavior by driving local apps.

- Capture browser `console.*` messages.
- Capture page errors and unhandled promise rejections.
- Capture navigation metadata: `url`, `pathname`, `route`, `screen_id`, and optional `user_journey`.
- Capture viewport and browser metadata when available.
- Include `browser_session_id` when a browser automation tool can provide one.
- Do not require a specific browser automation tool. The helper should work for manual browser sessions, Playwright sessions, Chrome DevTools Protocol sessions, and simple Vite dev browser sessions.

### Databases And Local Services

Database logs and local service diagnostics are in scope.

- Capture database container stdout/stderr for local Docker Compose databases.
- Capture database log files when configured by the application or test harness.
- Allow explicit app-level database diagnostic events through `POST /ingest/db`.
- Normalize database logs with `source="database"`.
- Include `db_system`, `db_name`, `service`, `container_name`, `app`, `worktree`, `agent_id`, and `run_id` when known.
- The E2E test should include at least one database-style event. A real database container is preferred if lightweight; otherwise a deterministic fake database log generator is acceptable for the MVP.

## Phoenix Trace Requirements

Add a basic local Arize Phoenix instance alongside the Victoria stack for optional trace inspection of LLM applications, MCP servers, Claude Code/Codex-adjacent harnesses, and instrumented app code. Phoenix is separate from VictoriaLogs/VictoriaMetrics: traces go to Phoenix, logs go to VictoriaLogs, and metrics go to VictoriaMetrics.

Phoenix requirements:

- Run `arizephoenix/phoenix` in Docker Compose with a pinned image version.
- Use a persistent `phoenix_data` volume.
- Prefer SQLite for the MVP by setting `PHOENIX_WORKING_DIR=/mnt/data`; Postgres can be a future profile if needed.
- Expose Phoenix UI at `http://127.0.0.1:6006`.
- Expose Phoenix OTLP HTTP at `http://127.0.0.1:6006/v1/traces`.
- Expose Phoenix OTLP gRPC internally on `phoenix:4317`.
- Set a short trace retention default with `PHOENIX_DEFAULT_RETENTION_POLICY_DAYS`, for example 7 days.
- Disable external analytics/telemetry where possible for local trusted development, for example `PHOENIX_TELEMETRY_ENABLED=false`.
- Enable Phoenix Prometheus metrics if useful for vmagent scraping, for example `PHOENIX_ENABLE_PROMETHEUS=true`. Phoenix exposes metrics at `/metrics` on its main HTTP port (6006).

<!-- RESOLVED(P3): Phoenix Prometheus metrics port 9090 is incorrect — Phoenix exposes metrics on its main port
REVIEW: Original text referenced port 9090. Phoenix actually serves `/metrics` on its main port (6006).
AUTHOR: Removed the incorrect port 9090 reference. vmagent scrapes `phoenix:6006/metrics` as configured in vmagent.yaml.
-->
- Do not configure Phoenix to forward traces into Victoria components.
- Keep Phoenix deployment, trace ingestion, and trace storage independent from the Victoria logs/metrics services.
- If future buffering, filtering, or redaction is needed for traces, add it within the Phoenix trace path only and keep it separate from Victoria.

Recommended trace flow:

```text
instrumented process -> OTEL_EXPORTER_OTLP_TRACES_ENDPOINT=http://127.0.0.1:6006/v1/traces -> Phoenix
```

Trace instrumentation examples:

- Python OpenInference/OpenTelemetry example for Anthropic.
- Python OpenInference/OpenTelemetry example for OpenAI SDK or OpenAI Agents/MCP.
- TypeScript OpenInference/OpenTelemetry example for Vercel AI SDK or Anthropic/OpenAI SDK when available.
- Generic environment-variable example:

```sh
export OTEL_EXPORTER_OTLP_TRACES_ENDPOINT=http://127.0.0.1:6006/v1/traces
export OTEL_EXPORTER_OTLP_PROTOCOL=http/protobuf
export OTEL_RESOURCE_ATTRIBUTES="service.name=my-app,app=my-app,worktree=$(basename "$PWD"),agent_id=${AGENT_ID:-unknown},run_id=${RUN_ID:-manual}"
```

## Metrics Requirements

Metrics are intentionally secondary to logs, but the repository should include a minimal metrics path.

- Run single-node VictoriaMetrics.
- Run `vmagent` with a scrape config.
- Scrape:
  - VictoriaLogs `/metrics`.
  - Vector Prometheus exporter `/metrics`.
  - Phoenix Prometheus metrics if `PHOENIX_ENABLE_PROMETHEUS=true`.
  - scratch app `/metrics`, if the scratch app exposes one.
  - browser-log example metrics, if implemented.
- Query metrics through a simple script, for example `scripts/query-metrics.sh 'up'`.
- Do not require Grafana for MVP.
- Metric query scripts must return JSON by default and exit non-zero when the query fails or returns no required data in assertion mode.
- Do not allow high-cardinality metric labels such as `run_id`, `screen_id`, or `url` unless a test explicitly proves the cardinality is bounded. Use logs for high-cardinality dimensions.

## E2E Test Requirements

The repository must include a script that can be run on a clean checkout:

```sh
./scripts/e2e.sh
```

The script must:

1. Generate a unique `E2E_RUN_ID`.
2. Start the Docker Compose stack with a unique compose project name.
3. Wait for VictoriaLogs, Vector, VictoriaMetrics, vmagent, and Phoenix to be healthy.
4. Run the backend/scratch log generator.
5. Run multiple parallel app/dev-server log emitters to simulate multiple agents driving separate runtime contexts.
6. Start the Vite browser-log example.
7. Send at least one frontend log through the Vite proxy path.
8. Send at least one synthetic OTLP trace directly to Phoenix and assert Phoenix accepts it.
9. Query VictoriaLogs through `http://127.0.0.1:9428/select/logsql/query`.
10. Assert backend/dev-server logs appear with the expected `run_id`, `agent_id`, `source`, and message marker.
11. Assert frontend logs appear with the expected `run_id`, `agent_id`, `screen_id`, and route.
12. Assert logs from parallel agent-driven runtime contexts remain distinguishable by `agent_id`, `run_id`, `worktree`, and `app`.
13. Query VictoriaMetrics for at least one expected scrape target or stack metric.
14. Print useful failure diagnostics:
    - `docker compose ps`
    - recent `victoria-logs` logs
    - recent `vector` logs
    - recent `phoenix` logs
    - failed query body and response
15. Tear down the stack unless `KEEP_STACK=1` is set.

### E2E Acceptance Criteria

- A clean run exits 0.
- A missing log exits non-zero with the query that failed.
- The script can be run repeatedly without using stale logs from a previous run.
- The test requires only Docker, Docker Compose, `curl`, and Node.js (>=18) on the host. The E2E script must check for these at startup and fail with a clear message if any are missing.

<!-- RESOLVED(P2): "local runtime needed by examples" is ambiguous — Node.js dependency should be explicit
REVIEW: "local runtime needed by examples" was too vague for preflight checks.
AUTHOR: Made Node.js (>=18) an explicit named dependency. The Vite browser-log example needs it, and agents need a concrete list to preflight-check.
-->
- If the default ports are already in use, the E2E script must fail early with a clear message naming the conflicting port and suggesting the user stop the running stack (`./scripts/down.sh`) or set custom ports via environment variables. The E2E script must use a unique Docker Compose project name (e.g. `agent-logs-e2e-{RUN_ID}`) so containers don't collide with a dev stack, but port isolation via automatic port discovery is not required for MVP.

<!-- RESOLVED(P2): E2E port isolation strategy undefined
REVIEW: Original text was ambiguous between automatic port isolation and early failure.
AUTHOR: MVP behavior is fail-early on port conflict with a helpful message. The compose project name is unique (preventing container-name collisions), but host ports use the same defaults. True port isolation (auto-discovery or offset ports) is deferred — it adds complexity without clear MVP value since agents typically run one stack at a time.
-->

## Agent Ergonomics

The repository must include copy-paste friendly commands:

```sh
./scripts/up.sh
./scripts/query-logs.sh 'run_id:run-123 AND error | limit 20'
./scripts/query-logs.sh '{app="scratch",agent_id="codex-a"} AND screen_id:checkout | limit 20'
./scripts/down.sh
```

CLI behavior requirements:

- Every script must support `--help`.
- Query scripts must default to the last 15 minutes (`--since 15m`) to protect agents from broad historical scans. Overridable with `--since`.
- Query scripts must accept a raw LogsQL or MetricsQL/PromQL-compatible query as the first argument.
- Query scripts must support `--since`, `--limit`, and `--timeout` when the underlying API supports them.
- Query scripts must print the exact API URL to stderr when `--verbose` is set.
- Query scripts must print only response data to stdout so agents can pipe it into `jq`, `rg`, or other tools.
- Assertion mode, for example `--expect`, must exit 0 on match and non-zero on no match.
- Failure messages must include the query, endpoint, HTTP status, and a compact response excerpt.
- Scripts must be deterministic and non-interactive.
- Scripts must not depend on terminal colors, pagers, TTY prompts, or browser sessions.

`README.md` should include:

- Quick start.
- Ingest examples with `curl`.
- Frontend Vite proxy example.
- Query examples.
- Agent-oriented command examples for emit, query, tail, and assert workflows.
- Reset instructions.
- Common troubleshooting steps.

## Reliability Requirements

- Vector must use bounded buffers.
- Vector must retry transient VictoriaLogs errors.
- Vector must prefer backpressure to dropping logs.
- E2E tests must use unique run IDs to avoid false positives from old data.
- Scripts must fail fast when required commands are missing.
- Scripts must print the exact URLs and ports they are using.
- Compose services must have restart policies suitable for local development, for example `unless-stopped` for normal stack services.

## Security Requirements

- No auth by design.
- No TLS by design.
- Bind published ports to `127.0.0.1` by default.
- Document that `AGENT_LOGS_BIND=0.0.0.0` exposes unauthenticated ingest and query APIs to the network.
- Do not log secrets in examples.
- Do not include real tokens, API keys, or sensitive environment dumps in tests.

## Performance Targets

These are local-development targets, not production SLOs.

- Handle at least 10 parallel agent-driven app/runtime contexts emitting logs at the same time.
- Handle bursts of at least 1,000 log events in a single E2E run.
- Make newly emitted logs queryable within 5 seconds under normal local Docker conditions.
- Keep the default stack small enough to run comfortably on a developer laptop.
- Keep E2E runtime under 2 minutes on a typical laptop after images are present.

## Implementation Notes

- VictoriaLogs calls the query language LogsQL. If scripts use the shorthand "LQL", document that it maps to VictoriaLogs LogsQL HTTP APIs.
- Prefer flat snake_case fields in emitted logs. Avoid nested objects unless Vector transforms flatten them consistently.
- Do not make `screen_id`, `url`, `route`, `task_id`, or `thread_id` stream fields unless cardinality is known to be low.
- Prefer stream fields that define stable producer identity and routing: `app`, `source`, and `service`. Keep `worktree` and `process_type` as queryable non-stream fields — their cardinality depends on the caller's workflow and cannot be bounded by the stack.
- Keep driver/session fields such as `agent_id`, `run_id`, `task_id`, and `thread_id` queryable but out of stream fields by default.
- Use `fields` and `limit` pipes in examples so agent queries return compact responses.
- Keep Grafana out of the MVP. CLI scripts and HTTP APIs are the product surface; VictoriaLogs Web UI is only a backup inspection tool.
- Prefer examples that can be copied directly into an agent prompt or shell command.
- Any generated diagnostics should be short enough to fit back into agent context.

## Reference URLs

- OpenAI harness engineering post: https://openai.com/index/harness-engineering/
- VictoriaLogs quick start: https://docs.victoriametrics.com/victorialogs/quickstart/
- VictoriaLogs data ingestion: https://docs.victoriametrics.com/victorialogs/data-ingestion/
- VictoriaLogs Vector setup: https://docs.victoriametrics.com/victorialogs/data-ingestion/vector/
- VictoriaLogs querying: https://docs.victoriametrics.com/victorialogs/querying/
- Vector HTTP server source: https://vector.dev/docs/reference/configuration/sources/http_server/
- Vector HTTP sink: https://vector.dev/docs/reference/configuration/sinks/http/
- Vector internal metrics source: https://vector.dev/docs/reference/configuration/sources/internal_metrics/
- Vector Prometheus exporter sink: https://vector.dev/docs/reference/configuration/sinks/prometheus_exporter/
- VictoriaMetrics vmagent: https://docs.victoriametrics.com/vmagent/
- Arize docs `llms.txt`: https://arize.com/docs/llms.txt
- Phoenix overview: https://arize.com/docs/phoenix
- Phoenix Docker self-hosting: https://arize.com/docs/phoenix/self-hosting/deployment-options/docker
- Phoenix self-hosting configuration: https://arize.com/docs/phoenix/self-hosting/configuration
- Phoenix tracing overview: https://arize.com/docs/phoenix/tracing/llm-traces
- Phoenix Anthropic tracing: https://arize.com/docs/phoenix/integrations/llm-providers/anthropic/anthropic-tracing
- Phoenix MCP tracing: https://arize.com/docs/phoenix/integrations/python/mcp-tracing

## Resolved Decisions

Decisions made during requirements refinement:

1. **VictoriaMetrics/vmagent**: included by default as MVP components.
2. **Driver identifier**: `agent_id` is the canonical field name.
3. **`run_id` scope**: caller-defined. The caller decides whether it represents a task, test run, session, or anything else. Document examples but don't enforce one meaning.
4. **`screen_id`**: app-supplied only. Not derived from routes.
5. **Browser logger**: both a shared `packages/browser-logger` package and an `examples/vite-browser-logs` example app.
6. **Log emission**: both direct HTTP ingest to Vector and `scripts/emit-log.sh` CLI wrapper.
7. **Docker stdout capture**: optional integration mode, not required for every app.
8. **File-tail source**: yes, via `scripts/tail-file.sh`.
9. **Default retention**: 7 days, configurable by env.
10. **Max concurrent agents**: at least 10 parallel contexts.
11. **E2E data cleanup**: unique `run_id` isolation is sufficient; no deletion needed.
12. **Query time default**: last 15 minutes by default, overridable with `--since`.
13. **Ports**: fixed by default (9428, 8688, etc.), configurable via env vars.
14. **Vite proxy target**: Vector directly, no intermediate proxy.
15. **Malformed browser payloads**: best-effort normalization, not rejection.
16. **Driver metadata** (`model`, `agent_tool`, `approval_mode`): included as optional recommended fields in the log schema.
17. **Trace IDs in logs**: `trace_id` and `span_id` are recommended (optional) output fields for future Phoenix correlation.
18. **Per-driver metric counters**: no. High-cardinality dimensions stay in logs/traces only.
19. **Live-tail script**: yes, `scripts/tail-logs.sh` is an MVP component.
20. **MCP tool for log querying**: post-MVP (added to Non-Goals).
21. **Trace sources**: all supported via generic OTEL env vars. No specific agent tooling source is required; the generic `OTEL_EXPORTER_OTLP_TRACES_ENDPOINT` pattern covers all cases.
22. **`agent_id`, `run_id`, `worktree` field status**: demoted from required to recommended. Auto-derived from env/hostname/cwd/git when absent. Required output fields are: `timestamp`, `level`, `message`, `source`, `app`, `service`.
