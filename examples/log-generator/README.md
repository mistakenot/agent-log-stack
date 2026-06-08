# @agent-logs/log-generator

Deterministic log generator for E2E tests. Emits logs to all Vector ingest paths with predictable marker messages.

## Usage

```bash
node generate.js --run-id=test-1 --agent-id=agent-1 --app=myapp
```

## Options

| Flag | Description |
|------|-------------|
| `--run-id` | Unique run identifier (required) |
| `--agent-id` | Agent identifier (required) |
| `--app` | Application name (required) |
| `--help` | Show help |

## Environment

| Variable | Default | Description |
|----------|---------|-------------|
| `AGENT_LOGS_URL` | `http://127.0.0.1:8688` | Vector HTTP ingest base URL |

## What it emits

Logs are sent to all four ingest paths:

- `POST /ingest/logs` — backend logs (3 events)
- `POST /ingest/browser` — browser logs (2 events)
- `POST /ingest/process` — process logs (2 events)
- `POST /ingest/db` — database logs (2 events, includes `db_system` and `db_name`)

Each source includes a deterministic marker message: `e2e_marker_<source>_<run_id>`

Logs are emitted with two agent contexts (`<agent_id>` and `<agent_id>-parallel`) to support parallel agent testing.

## Exit codes

- `0` — all logs emitted successfully
- `1` — HTTP error or missing arguments
