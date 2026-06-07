import type { Plugin, IndexHtmlTransformResult } from "vite";

export interface AgentLogsOptions {
  /**
   * Target URL for the agent-logs Vector ingest endpoint.
   * Defaults to process.env.AGENT_LOGS_URL or http://127.0.0.1:8688
   */
  target?: string;

  /**
   * Application name passed to browser-logger when inject is true.
   */
  app?: string;

  /**
   * If true, inject a script tag with browser-logger initialization into HTML
   * responses during dev mode (via transformIndexHtml hook).
   * Default: false
   */
  inject?: boolean;
}

/**
 * Vite plugin that configures the /__agent_logs/browser proxy to forward
 * browser log events to the agent-logs Vector ingest endpoint, and optionally
 * injects the browser-logger script in dev mode.
 */
export default function agentLogs(options?: AgentLogsOptions): Plugin {
  const target =
    options?.target ??
    process.env.AGENT_LOGS_URL ??
    "http://127.0.0.1:8688";
  const app = options?.app ?? "app";
  const inject = options?.inject ?? false;

  return {
    name: "agent-logs",

    config() {
      return {
        server: {
          proxy: {
            "/__agent_logs/browser": {
              target,
              changeOrigin: true,
              rewrite: () => "/ingest/browser",
            },
          },
        },
      };
    },

    transformIndexHtml(html) {
      if (!inject) {
        return html;
      }

      const tags: IndexHtmlTransformResult = [
        {
          tag: "script",
          attrs: { type: "module" },
          children: `import { createLogger } from "@agent-logs/browser-logger";\nwindow.__agentLogger = createLogger({ app: ${JSON.stringify(app)} });`,
          injectTo: "head",
        },
      ];

      return tags;
    },
  };
}
