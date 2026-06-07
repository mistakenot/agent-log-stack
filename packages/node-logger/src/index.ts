import { hostname } from "node:os";
import { basename } from "node:path";

export interface LoggerConfig {
  url?: string;
  app: string;
  service?: string;
  source?: string;
  agentId?: string;
  runId?: string;
  worktree?: string;
}

export interface Logger {
  info(...args: unknown[]): void;
  warn(...args: unknown[]): void;
  error(...args: unknown[]): void;
  log(...args: unknown[]): void;
}

interface LogPayload {
  timestamp: string;
  level: string;
  message: string;
  app: string;
  service: string;
  source: string;
  pid: number;
  hostname: string;
  process_name: string;
  agent_id?: string;
  run_id?: string;
  worktree?: string;
}

function formatMessage(args: unknown[]): string {
  return args
    .map((a) => (typeof a === "string" ? a : JSON.stringify(a)))
    .join(" ");
}

function post(url: string, payload: LogPayload): void {
  // Fire-and-forget: do not await, do not throw on failure
  fetch(url, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(payload),
  }).catch(() => {
    // Silently ignore network errors
  });
}

export function createLogger(config: LoggerConfig): Logger {
  const url =
    config.url ||
    process.env.AGENT_LOGS_URL ||
    "http://127.0.0.1:8688";
  const ingestUrl = `${url.replace(/\/$/, "")}/ingest/logs`;

  const app = config.app || process.env.APP || "unknown";
  const service = config.service || process.env.SERVICE || "default";
  const source = config.source || "backend";
  const agentId = config.agentId || process.env.AGENT_ID;
  const runId = config.runId || process.env.RUN_ID;
  const worktree = config.worktree || process.env.WORKTREE;

  const pid = process.pid;
  const host = hostname();
  const processName = basename(process.argv[1] || process.argv[0]);

  function emit(level: string, args: unknown[]): void {
    const payload: LogPayload = {
      timestamp: new Date().toISOString(),
      level,
      message: formatMessage(args),
      app,
      service,
      source,
      pid,
      hostname: host,
      process_name: processName,
    };

    if (agentId) payload.agent_id = agentId;
    if (runId) payload.run_id = runId;
    if (worktree) payload.worktree = worktree;

    post(ingestUrl, payload);
  }

  return {
    info(...args: unknown[]): void {
      console.info(...args);
      emit("info", args);
    },
    warn(...args: unknown[]): void {
      console.warn(...args);
      emit("warn", args);
    },
    error(...args: unknown[]): void {
      console.error(...args);
      emit("error", args);
    },
    log(...args: unknown[]): void {
      console.log(...args);
      emit("info", args);
    },
  };
}
