/**
 * @agent-logs/browser-logger
 *
 * Tiny browser-side logging helper that captures console output and errors
 * and ships them to the agent-logs stack via HTTP POST.
 */

export interface BrowserLoggerConfig {
  /** POST endpoint for log events (default: "/__agent_logs/browser") */
  endpoint?: string;
  /** Application name (required) */
  app: string;
  /** Current screen identifier */
  screenId?: string;
  /** Agent identifier */
  agentId?: string;
  /** Run identifier */
  runId?: string;
  /** Worktree path */
  worktree?: string;
  /** Batch size — reserved for future batch mode (currently sends one event per POST) */
  batchSize?: number;
  /** Flush interval in ms — reserved for future batch mode */
  flushInterval?: number;
}

export interface LogEvent {
  timestamp: string;
  level: string;
  message: string;
  source: string;
  app: string;
  service: string;
  screen_id?: string;
  route: string;
  url: string;
  user_agent: string;
  viewport: string;
  agent_id?: string;
  run_id?: string;
  worktree?: string;
  [key: string]: unknown;
}

export interface Logger {
  info(message: string, extra?: Record<string, unknown>): void;
  warn(message: string, extra?: Record<string, unknown>): void;
  error(message: string, extra?: Record<string, unknown>): void;
  /** Remove global error listeners installed by this logger */
  destroy(): void;
}

function getMetadata(config: BrowserLoggerConfig): Pick<LogEvent, "route" | "url" | "user_agent" | "viewport" | "screen_id" | "agent_id" | "run_id" | "worktree"> {
  return {
    route: typeof window !== "undefined" ? window.location.pathname : "",
    url: typeof window !== "undefined" ? window.location.href : "",
    user_agent: typeof navigator !== "undefined" ? navigator.userAgent : "",
    viewport: typeof window !== "undefined" ? `${window.innerWidth}x${window.innerHeight}` : "",
    ...(config.screenId != null ? { screen_id: config.screenId } : {}),
    ...(config.agentId != null ? { agent_id: config.agentId } : {}),
    ...(config.runId != null ? { run_id: config.runId } : {}),
    ...(config.worktree != null ? { worktree: config.worktree } : {}),
  };
}

function sendEvent(endpoint: string, event: LogEvent): void {
  try {
    if (typeof fetch !== "undefined") {
      fetch(endpoint, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify(event),
        keepalive: true,
      }).catch(() => {
        // Silently drop — logging should never break the app
      });
    }
  } catch {
    // Silently drop
  }
}

function buildEvent(
  config: BrowserLoggerConfig,
  level: string,
  message: string,
  extra?: Record<string, unknown>,
): LogEvent {
  return {
    timestamp: new Date().toISOString(),
    level,
    message,
    source: "browser",
    app: config.app,
    service: "browser",
    ...getMetadata(config),
    ...(extra ?? {}),
  };
}

/**
 * Create a browser logger instance.
 *
 * Installs global handlers for unhandled errors and unhandled promise rejections.
 * Call `logger.destroy()` to remove those handlers.
 */
export function createLogger(config: BrowserLoggerConfig): Logger {
  const endpoint = config.endpoint ?? "/__agent_logs/browser";

  // Global error handler
  const onError = (event: ErrorEvent): void => {
    const message = event.message || "Unhandled error";
    const ev = buildEvent(config, "error", message, {
      error_filename: event.filename ?? "",
      error_lineno: event.lineno ?? 0,
      error_colno: event.colno ?? 0,
      error_stack: event.error?.stack ?? "",
    });
    sendEvent(endpoint, ev);
  };

  // Unhandled promise rejection handler
  const onUnhandledRejection = (event: PromiseRejectionEvent): void => {
    const reason = event.reason;
    const message =
      reason instanceof Error
        ? reason.message
        : typeof reason === "string"
          ? reason
          : "Unhandled promise rejection";
    const ev = buildEvent(config, "error", message, {
      error_stack: reason instanceof Error ? (reason.stack ?? "") : "",
      rejection: true,
    });
    sendEvent(endpoint, ev);
  };

  if (typeof window !== "undefined") {
    window.addEventListener("error", onError);
    window.addEventListener("unhandledrejection", onUnhandledRejection);
  }

  const logger: Logger = {
    info(message: string, extra?: Record<string, unknown>): void {
      const ev = buildEvent(config, "info", message, extra);
      sendEvent(endpoint, ev);
    },

    warn(message: string, extra?: Record<string, unknown>): void {
      const ev = buildEvent(config, "warn", message, extra);
      sendEvent(endpoint, ev);
    },

    error(message: string, extra?: Record<string, unknown>): void {
      const ev = buildEvent(config, "error", message, extra);
      sendEvent(endpoint, ev);
    },

    destroy(): void {
      if (typeof window !== "undefined") {
        window.removeEventListener("error", onError);
        window.removeEventListener("unhandledrejection", onUnhandledRejection);
      }
    },
  };

  return logger;
}
