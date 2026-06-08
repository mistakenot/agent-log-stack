#!/usr/bin/env node
// @agent-logs/log-generator
// Deterministic log generator for E2E tests. Emits OTLP log records to Vector.
// Usage: node generate.js --run-id=<id> --agent-id=<id> --app=<name>

const AGENT_LOGS_URL = process.env.AGENT_LOGS_URL || "http://127.0.0.1:4318";

// --- Argument parsing ---

function parseArgs(argv) {
  const args = {};
  for (const arg of argv.slice(2)) {
    if (arg === "--help" || arg === "-h") {
      args.help = true;
      continue;
    }
    const match = arg.match(/^--([^=]+)=(.*)$/);
    if (match) {
      args[match[1].replace(/-/g, "_")] = match[2];
    }
  }
  return args;
}

function printHelp() {
  const help = `Usage: node generate.js --run-id=<id> --agent-id=<id> --app=<name>

Generates deterministic logs across all sources via OTLP for E2E testing.

Options:
  --run-id     Unique run identifier (required)
  --agent-id   Agent identifier (required)
  --app        Application name (required)
  --help       Show this help message

Environment:
  AGENT_LOGS_URL  Base URL for OTLP HTTP ingest (default: http://127.0.0.1:4318)

Each source emits a deterministic marker: e2e_marker_<source>_<run_id>
Logs are emitted with two agent contexts: <agent_id> and <agent_id>-parallel
`;
  process.stderr.write(help);
}

// --- OTLP helpers ---

const SEVERITY_MAP = {
  trace: 1,
  debug: 5,
  info: 9,
  warn: 13,
  error: 17,
  fatal: 21,
};

function buildOtlpPayload(log) {
  // Resource attributes: service.name and app
  const resourceAttributes = [
    { key: "service.name", value: { stringValue: log.service } },
    { key: "app", value: { stringValue: log.app } },
  ];

  // Log record attributes: all extra fields
  const logAttributes = [];
  const attrFields = ["source", "agent_id", "run_id", "screen_id", "db_system", "db_name", "worktree"];
  for (const field of attrFields) {
    if (log[field] !== undefined) {
      logAttributes.push({ key: field, value: { stringValue: log[field] } });
    }
  }

  const timeUnixNano = String(Date.now() * 1000000);

  return {
    resourceLogs: [
      {
        resource: { attributes: resourceAttributes },
        scopeLogs: [
          {
            scope: {},
            logRecords: [
              {
                timeUnixNano,
                severityText: log.level.toUpperCase(),
                severityNumber: SEVERITY_MAP[log.level] || 9,
                body: { stringValue: log.message },
                attributes: logAttributes,
              },
            ],
          },
        ],
      },
    ],
  };
}

// --- Log generation ---

async function postLog(log) {
  const url = `${AGENT_LOGS_URL}/v1/logs`;
  const payload = buildOtlpPayload(log);
  const response = await fetch(url, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(payload),
  });
  if (!response.ok) {
    const text = await response.text().catch(() => "");
    throw new Error(`POST /v1/logs failed: ${response.status} ${response.statusText} - ${text}`);
  }
  return response;
}

function makeTimestamp(offsetMs = 0) {
  return new Date(Date.now() + offsetMs).toISOString();
}

async function emitBackendLogs(runId, agentId, app) {
  const logs = [
    {
      timestamp: makeTimestamp(0),
      level: "info",
      message: `e2e_marker_backend_${runId}`,
      source: "backend",
      app,
      service: "api",
      agent_id: agentId,
      run_id: runId,
    },
    {
      timestamp: makeTimestamp(1),
      level: "debug",
      message: `Backend processing request for run ${runId}`,
      source: "backend",
      app,
      service: "api",
      agent_id: agentId,
      run_id: runId,
    },
    {
      timestamp: makeTimestamp(2),
      level: "warn",
      message: `Slow query detected in run ${runId}`,
      source: "backend",
      app,
      service: "worker",
      agent_id: `${agentId}-parallel`,
      run_id: runId,
    },
  ];

  for (const log of logs) {
    await postLog(log);
  }
  return logs.length;
}

async function emitBrowserLogs(runId, agentId, app) {
  const logs = [
    {
      timestamp: makeTimestamp(10),
      level: "info",
      message: `e2e_marker_browser_${runId}`,
      source: "browser",
      app,
      service: "web-ui",
      agent_id: agentId,
      run_id: runId,
      screen_id: "dashboard",
    },
    {
      timestamp: makeTimestamp(11),
      level: "error",
      message: `Uncaught TypeError in component render`,
      source: "browser",
      app,
      service: "web-ui",
      agent_id: `${agentId}-parallel`,
      run_id: runId,
      screen_id: "settings",
    },
  ];

  for (const log of logs) {
    await postLog(log);
  }
  return logs.length;
}

async function emitProcessLogs(runId, agentId, app) {
  const logs = [
    {
      timestamp: makeTimestamp(20),
      level: "info",
      message: `e2e_marker_process_${runId}`,
      source: "process",
      app,
      service: "build",
      agent_id: agentId,
      run_id: runId,
    },
    {
      timestamp: makeTimestamp(21),
      level: "info",
      message: `Process spawned: npm run build (pid=12345)`,
      source: "process",
      app,
      service: "build",
      agent_id: `${agentId}-parallel`,
      run_id: runId,
    },
  ];

  for (const log of logs) {
    await postLog(log);
  }
  return logs.length;
}

async function emitDatabaseLogs(runId, agentId, app) {
  const logs = [
    {
      timestamp: makeTimestamp(30),
      level: "info",
      message: `e2e_marker_database_${runId}`,
      source: "database",
      app,
      service: "postgres",
      agent_id: agentId,
      run_id: runId,
      db_system: "postgresql",
      db_name: "app_db",
    },
    {
      timestamp: makeTimestamp(31),
      level: "warn",
      message: `Long-running transaction detected (duration=3200ms)`,
      source: "database",
      app,
      service: "postgres",
      agent_id: `${agentId}-parallel`,
      run_id: runId,
      db_system: "postgresql",
      db_name: "app_db",
    },
  ];

  for (const log of logs) {
    await postLog(log);
  }
  return logs.length;
}

// --- Main ---

async function main() {
  const args = parseArgs(process.argv);

  if (args.help) {
    printHelp();
    process.exit(0);
  }

  if (!args.run_id || !args.agent_id || !args.app) {
    process.stderr.write("Error: --run-id, --agent-id, and --app are required.\n");
    process.stderr.write("Run with --help for usage information.\n");
    process.exit(1);
  }

  const { run_id: runId, agent_id: agentId, app } = args;
  const counts = {};

  try {
    counts.backend = await emitBackendLogs(runId, agentId, app);
    counts.browser = await emitBrowserLogs(runId, agentId, app);
    counts.process = await emitProcessLogs(runId, agentId, app);
    counts.database = await emitDatabaseLogs(runId, agentId, app);
  } catch (err) {
    process.stderr.write(`Error: ${err.message}\n`);
    process.exit(1);
  }

  const total = Object.values(counts).reduce((a, b) => a + b, 0);
  const summary = [
    `Emitted ${total} OTLP log records to ${AGENT_LOGS_URL}/v1/logs:`,
    `  backend:  ${counts.backend}`,
    `  browser:  ${counts.browser}`,
    `  process:  ${counts.process}`,
    `  database: ${counts.database}`,
    `Markers:`,
    `  e2e_marker_backend_${runId}`,
    `  e2e_marker_browser_${runId}`,
    `  e2e_marker_process_${runId}`,
    `  e2e_marker_database_${runId}`,
    `Agent contexts: ${agentId}, ${agentId}-parallel`,
    "",
  ].join("\n");

  process.stderr.write(summary);
  process.exit(0);
}

main();
