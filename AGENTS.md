# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What This Repo Is

Local observability stack for development environments driven by AI coding agents. Collects logs, metrics, and traces from **apps and runtimes the agent is driving** — not the agent's own chat history. The primary user is an agent calling CLI tools and HTTP endpoints, not a human watching dashboards.

## Stack Commands

```bash
# Start everything (preflight checks, docker compose up, prints URLs)
./start.sh

# Individual lifecycle
./scripts/up.sh          # docker compose up -d
./scripts/down.sh        # docker compose down
./scripts/reset.sh       # docker compose down -v (wipes all data)
```

## Services and Ports

All ports bind to `127.0.0.1` by default. Configured via `.env` (copied from `.env.example` on first start).

| Service | Port | Purpose |
|---------|------|---------|
| VictoriaLogs | 9428 | Log storage + LogsQL query API |
| Vector | 8688 | HTTP log ingest (all `/ingest/*` paths) |
| Vector metrics | 9598 | Prometheus metrics exporter |
| VictoriaMetrics | 8428 | Metrics storage + PromQL query API |
| Phoenix | 6006 | Trace UI + OTLP HTTP (`/v1/traces`) |
| Phoenix gRPC | 4317 | OTLP gRPC collector |

## Sending Logs

POST JSON to Vector. The URL path determines the `source` field:

```bash
# Backend/app logs (source=backend)
curl -X POST http://127.0.0.1:8688/ingest/logs -H 'Content-Type: application/json' \
  -d '{"message":"hello","app":"myapp","service":"api"}'

# Browser logs (source=browser)
curl -X POST http://127.0.0.1:8688/ingest/browser -H 'Content-Type: application/json' \
  -d '{"message":"click","app":"myapp","screen_id":"checkout"}'

# Database logs (source=database)  → /ingest/db
# Process logs (source=process)    → /ingest/process
```

## Querying Logs

```bash
curl -s 'http://127.0.0.1:9428/select/logsql/query' \
  -d 'query={app="myapp",source="backend"} | limit 10'
```

## Architecture

```
app/browser/process → POST /ingest/* → Vector (8688)
    → VRL normalize (defaults for timestamp, level, message, source, app, service)
    → VictoriaLogs /insert/jsonline (9428)
    → LogsQL query API

vmagent scrapes /metrics from: victoria-logs, vector, victoria-metrics, phoenix
    → VictoriaMetrics (8428)

instrumented app → OTLP → Phoenix (6006)
```

**Vector config**: `config/vector.yaml` — single `http_server` source with `strict_path: false`, VRL transform for normalization, HTTP sink to VictoriaLogs with gzip + disk buffer.

**VictoriaLogs sink URL** includes `_stream_fields=app,source,service`. Do not add high-cardinality fields (`agent_id`, `run_id`, `screen_id`) to stream fields.

## Log Schema

**Required fields** (Vector sets defaults if missing): `timestamp`, `level`, `message`, `source`, `app`, `service`.

**Recommended fields** (optional, for filtering): `agent_id`, `run_id`, `worktree`, `screen_id`, plus many others listed in `requirements.md`.

## Key Files

- `requirements.md` — full spec, schema contract, resolved design decisions
- `docker-compose.yml` — all 5 services, health checks, volumes
- `config/vector.yaml` — ingest routes, VRL normalization, VictoriaLogs sink
- `config/vmagent.yaml` — Prometheus scrape targets
- `.env.example` — pinned image versions, ports, retention

## What's Not Built Yet

The requirements.md specifies these components that don't exist yet:

- `scripts/query-logs.sh`, `scripts/emit-log.sh`, `scripts/tail-logs.sh`, `scripts/tail-file.sh`, `scripts/query-metrics.sh`, `scripts/discover-app.sh`
- `scripts/e2e.sh` and `tests/e2e/`
- `packages/browser-logger`, `packages/node-logger`, `packages/vite-plugin-agent-logs`
- `examples/log-generator`, `examples/vite-browser-logs`
- `README.md`

## Development Notes

- Image versions are pinned in `.env.example`. After changing, run `docker compose pull`.
- Vector VRL is strict about error coalescing (`??`) — use `if !exists(.field)` patterns instead.
- Health checks use `wget` (VictoriaLogs/Vector/VictoriaMetrics alpine images) or `python3` (Phoenix).
- VictoriaLogs health check must use `127.0.0.1` not `localhost` (IPv6 resolution fails in containers).

<!-- br-agent-instructions-v1 -->

---

## Beads Workflow Integration

This project uses [beads_rust](https://github.com/Dicklesworthstone/beads_rust) (`br`/`bd`) for issue tracking. Issues are stored in `.beads/` and tracked in git.

### Essential Commands

```bash
# View ready issues (open, unblocked, not deferred)
br ready              # or: bd ready

# List and search
br list --status=open # All open issues
br show <id>          # Full issue details with dependencies
br search "keyword"   # Full-text search

# Create and update
br create --title="..." --description="..." --type=task --priority=2
br update <id> --status=in_progress
br close <id> --reason="Completed"
br close <id1> <id2>  # Close multiple issues at once

# Sync with git
br sync --flush-only  # Export DB to JSONL
br sync --status      # Check sync status
```

### Workflow Pattern

1. **Start**: Run `br ready` to find actionable work
2. **Claim**: Use `br update <id> --status=in_progress`
3. **Work**: Implement the task
4. **Complete**: Use `br close <id>`
5. **Sync**: Always run `br sync --flush-only` at session end

### Key Concepts

- **Dependencies**: Issues can block other issues. `br ready` shows only open, unblocked work.
- **Priority**: P0=critical, P1=high, P2=medium, P3=low, P4=backlog (use numbers 0-4, not words)
- **Types**: task, bug, feature, epic, chore, docs, question
- **Blocking**: `br dep add <issue> <depends-on>` to add dependencies

### Session Protocol

**Before ending any session, run this checklist:**

```bash
git status              # Check what changed
git add <files>         # Stage code changes
br sync --flush-only    # Export beads changes to JSONL
git commit -m "..."     # Commit everything
git push                # Push to remote
```

### Best Practices

- Check `br ready` at session start to find available work
- Update status as you work (in_progress → closed)
- Create new issues with `br create` when you discover tasks
- Use descriptive titles and set appropriate priority/type
- Always sync before ending session

<!-- end-br-agent-instructions -->

<!-- bv-agent-instructions-v2 -->

---

## Beads Workflow Integration

This project uses [beads_rust](https://github.com/Dicklesworthstone/beads_rust) (`br`) for issue tracking and [beads_viewer](https://github.com/Dicklesworthstone/beads_viewer) (`bv`) for graph-aware triage. Issues are stored in `.beads/` and tracked in git.

### Using bv as an AI sidecar

bv is a graph-aware triage engine for Beads projects (.beads/beads.jsonl). Instead of parsing JSONL or hallucinating graph traversal, use robot flags for deterministic, dependency-aware outputs with precomputed metrics (PageRank, betweenness, critical path, cycles, HITS, eigenvector, k-core).

**Scope boundary:** bv handles *what to work on* (triage, priority, planning). `br` handles creating, modifying, and closing beads.

**CRITICAL: Use ONLY --robot-* flags. Bare bv launches an interactive TUI that blocks your session.**

#### The Workflow: Start With Triage

**`bv --robot-triage` is your single entry point.** It returns everything you need in one call:
- `quick_ref`: at-a-glance counts + top 3 picks
- `recommendations`: ranked actionable items with scores, reasons, unblock info
- `quick_wins`: low-effort high-impact items
- `blockers_to_clear`: items that unblock the most downstream work
- `project_health`: status/type/priority distributions, graph metrics
- `commands`: copy-paste shell commands for next steps

```bash
bv --robot-triage        # THE MEGA-COMMAND: start here
bv --robot-next          # Minimal: just the single top pick + claim command

# Token-optimized output (TOON) for lower LLM context usage:
bv --robot-triage --format toon
```

#### Other bv Commands

| Command | Returns |
|---------|---------|
| `--robot-plan` | Parallel execution tracks with unblocks lists |
| `--robot-priority` | Priority misalignment detection with confidence |
| `--robot-insights` | Full metrics: PageRank, betweenness, HITS, eigenvector, critical path, cycles, k-core |
| `--robot-alerts` | Stale issues, blocking cascades, priority mismatches |
| `--robot-suggest` | Hygiene: duplicates, missing deps, label suggestions, cycle breaks |
| `--robot-diff --diff-since <ref>` | Changes since ref: new/closed/modified issues |
| `--robot-graph [--graph-format=json\|dot\|mermaid]` | Dependency graph export |

#### Scoping & Filtering

```bash
bv --robot-plan --label backend              # Scope to label's subgraph
bv --robot-insights --as-of HEAD~30          # Historical point-in-time
bv --recipe actionable --robot-plan          # Pre-filter: ready to work (no blockers)
bv --recipe high-impact --robot-triage       # Pre-filter: top PageRank scores
```

### br Commands for Issue Management

```bash
br ready              # Show issues ready to work (no blockers)
br list --status=open # All open issues
br show <id>          # Full issue details with dependencies
br create --title="..." --type=task --priority=2
br update <id> --status=in_progress
br close <id> --reason="Completed"
br close <id1> <id2>  # Close multiple issues at once
br sync --flush-only  # Export DB to JSONL
```

### Workflow Pattern

1. **Triage**: Run `bv --robot-triage` to find the highest-impact actionable work
2. **Claim**: Use `br update <id> --status=in_progress`
3. **Work**: Implement the task
4. **Complete**: Use `br close <id>`
5. **Sync**: Always run `br sync --flush-only` at session end

### Key Concepts

- **Dependencies**: Issues can block other issues. `br ready` shows only unblocked work.
- **Priority**: P0=critical, P1=high, P2=medium, P3=low, P4=backlog (use numbers 0-4, not words)
- **Types**: task, bug, feature, epic, chore, docs, question
- **Blocking**: `br dep add <issue> <depends-on>` to add dependencies

### Session Protocol

```bash
git status              # Check what changed
git add <files>         # Stage code changes
br sync --flush-only    # Export beads changes to JSONL
git commit -m "..."     # Commit everything
git push                # Push to remote
```

<!-- end-bv-agent-instructions -->
