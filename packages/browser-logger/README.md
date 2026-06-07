# @agent-logs/browser-logger

Tiny browser-side logging helper that captures console output and errors and ships them to the agent-logs stack.

## Installation

```bash
npm install @agent-logs/browser-logger
```

## Usage

```typescript
import { createLogger } from "@agent-logs/browser-logger";

const logger = createLogger({
  app: "my-app",
  screenId: "checkout",
  agentId: "agent-123",
});

logger.info("Page loaded", { component: "App" });
logger.warn("Slow network detected");
logger.error("Payment failed", { code: "TIMEOUT" });

// Unhandled errors and promise rejections are captured automatically.

// To remove global listeners:
logger.destroy();
```

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `app` | `string` | (required) | Application name |
| `endpoint` | `string` | `"/__agent_logs/browser"` | POST endpoint for log events |
| `screenId` | `string` | — | Current screen identifier |
| `agentId` | `string` | — | Agent identifier |
| `runId` | `string` | — | Run identifier |
| `worktree` | `string` | — | Worktree path |

## Vite Proxy

Configure your Vite dev server to proxy the endpoint to Vector:

```typescript
// vite.config.ts
export default defineConfig({
  server: {
    proxy: {
      "/__agent_logs/browser": {
        target: "http://127.0.0.1:8688/ingest/browser",
        changeOrigin: true,
        rewrite: (path) => path.replace(/^\/__agent_logs\/browser/, ""),
      },
    },
  },
});
```
